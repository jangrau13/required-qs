#!/bin/sh
# Delivering the same message more than once, and counting what got done.
#
# The queue and the store come from /scenarios/fakes.py rather than from a
# second copy written here. The repository declares that API and supplies none
# of it, so the candidate wrote `handle` against exactly that shape, and two
# definitions of it would eventually disagree about what their code does.
#
# These report what the consumer did rather than marking it: work applied twice
# is a count to ask about, not a failure. A non-zero exit means the consumer
# could not be run at all — and the counts are what the required questions have
# to be answered against.
#
# The probe is written into /build: /work belongs to root so that a submission
# cannot rewrite itself while it is being run, and /tmp is noexec.
#
# Usage: run.sh --list | run.sh [replay-after-apply|replay-after-record|lost-work|redeliver|two-messages]
set -eu

if [ "${1:-}" = "--list" ]; then
  printf 'replay-after-apply\tCrashes handle() between applying the work and recording that it was applied, then delivers the same message again. Counts applications and acknowledgements on both sides of the crash.\n'
  printf 'replay-after-record\tCrashes handle() between recording the work and acknowledging the message, then delivers it again. The queue never heard the ack, so the work must not happen a second time.\n'
  printf 'lost-work\tThe same crash, but the message comes back only if the queue never heard an acknowledgement — which is the only redelivery a real queue makes. Work acknowledged before it was durable is lost here, and nothing else shows that.\n'
  printf 'redeliver\tDelivers the same message twice with no crash anywhere. This is the visibility timeout expiring while handle() was still running, and it costs whatever the count says it costs.\n'
  printf 'two-messages\tDelivers two different messages and checks that both were applied and both acknowledged. Catches a consumer that dedupes on the wrong thing and silently drops the second one.\n'
  exit 0
fi

TARGET="${1:-replay-after-apply}"
case "$TARGET" in
  replay-after-apply | replay-after-record | lost-work | redeliver | two-messages) ;;
  *) echo "no such target: $TARGET"; exit 2 ;;
esac

mkdir -p "${TMPDIR:-/build/tmp}"
[ -f /work/consumer.py ] || { echo "the submission has no consumer.py at its root"; exit 2; }
[ -f /scenarios/fakes.py ] || {
  echo "this assignment's queue and store live in /scenarios/fakes.py, which is not mounted"
  exit 2
}

W=/build/viva-run
rm -rf "$W"; mkdir -p "$W"

cat > "$W/probe.py" <<'PY'
import sys

sys.path.insert(0, "/scenarios")

from fakes import Crash, Message, Queue, Store, load  # noqa: E402

Consumer = load()
target = sys.argv[1]


def deliver(queue, store, message):
    """One delivery, through a consumer that remembers nothing between them.

    A fresh instance every time on purpose: state kept in the consumer does not
    survive the crash these targets are about, so a submission that dedupes in
    memory must not be able to pass by accident.
    """
    try:
        Consumer(queue, store).handle(message)
    except Crash as c:
        print(f"crashed: {c}")
        return "crash"
    except NotImplementedError:
        print("the submission does not implement handle()")
        raise SystemExit(4)
    except Exception as e:  # noqa: BLE001
        print(f"handle() raised {type(e).__name__}: {e}")
        raise SystemExit(1)
    return "returned"


def state(store, queue, when):
    print(f"{when} applied={store.applied} recorded={sorted(store.recorded)} acked={queue.acked}")


def verdict(store, queue):
    """Once, and acknowledged. Anything else is what the candidate explains."""
    if len(store.applied) != 1:
        print(f"APPLIED {len(store.applied)} TIMES — the work is not done exactly once")
    elif not queue.acked:
        print("NEVER ACKNOWLEDGED — the queue will deliver this message again")
    else:
        print("applied once, and acknowledged")


if target in ("replay-after-apply", "replay-after-record"):
    at = "after-apply" if target == "replay-after-apply" else "after-record"
    q, s = Queue(), Store(crash_at=at)
    m = Message("m-1", "charge 500")

    if deliver(q, s, m) != "crash":
        print(f"handle() returned without dying at the {at} point")
    state(s, q, "after the crash: ")

    s.crash_at = None
    deliver(q, s, m)
    state(s, q, "after redelivery:")
    verdict(s, q)

if target == "lost-work":
    # The other crash targets redeliver because the script says so. A queue
    # redelivers because it heard no acknowledgement, and that difference is
    # the whole of what acknowledging too early costs: the message never comes
    # back, and the work that was rolled back with the crash is simply gone.
    q, s = Queue(), Store(crash_at="after-apply")
    m = Message("m-1", "charge 500")

    deliver(q, s, m)
    state(s, q, "after the crash: ")

    if q.acked:
        print("the queue heard an acknowledgement, so it will not deliver this message again")
    else:
        s.crash_at = None
        deliver(q, s, m)
        state(s, q, "after redelivery:")

    if not s.applied:
        print("ACKNOWLEDGED AND LOST — the queue was told this was done, and the work was rolled back with the crash")
    else:
        verdict(s, q)

if target == "redeliver":
    q, s = Queue(), Store()
    m = Message("m-1", "charge 500")

    deliver(q, s, m)
    state(s, q, "after the first delivery: ")
    deliver(q, s, m)
    state(s, q, "after the second delivery:")
    verdict(s, q)

if target == "two-messages":
    q, s = Queue(), Store()
    for mid, body in (("m-1", "charge 500"), ("m-2", "charge 700")):
        deliver(q, s, Message(mid, body))
    state(s, q, "after both deliveries:")

    if len(s.applied) != 2:
        print(f"TWO MESSAGES, {len(s.applied)} APPLIED — a second, different message was dropped")
    elif len(q.acked) != 2:
        print(f"TWO MESSAGES, {len(q.acked)} ACKNOWLEDGED — the queue will deliver one of them again")
    else:
        print("both messages were applied, and both were acknowledged")
PY

python3 "$W/probe.py" "$TARGET" 2>&1
