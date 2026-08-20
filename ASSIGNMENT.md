# Drain the queue (example assignment)

The queue redelivers anything you do not acknowledge before the visibility
timeout expires. Your consumer must cope with that.

Your problem is `consumer.py`, and one method in it.

## What to do

1. **`Consumer.handle(message)`** — apply `message.body` to the store and
   acknowledge the message.
2. A message delivered twice must not apply its work twice.

## What you are marked on

Not that it runs — there is nothing here to run it against. You are marked on
whether you can explain, in a viva, what a crash between any two of your
statements would cost.
