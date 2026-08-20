"""Draining a work queue without losing or repeating jobs.

The queue redelivers anything not acknowledged before the visibility timeout.
`handle` is the part with a decision in it.
"""


class Consumer:
    def __init__(self, queue, store):
        self.queue = queue
        self.store = store

    def handle(self, message) -> None:
        """Do the work in `message` and acknowledge it."""
        raise NotImplementedError
