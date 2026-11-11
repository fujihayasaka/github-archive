import logging
from sink import SinkException
from pypi_package_archive import InvalidArchiveError
from collections import namedtuple
from threading import Thread
from queue import Queue

ImportSpec = namedtuple('ImportSpec', ['package_name', 'version'])


class Worker:
    """
    A thread worker to shovel releases from the PyPI into the Sink.
    """

    @classmethod
    def process_specs(cls, import_specs, client, sink, num_threads):
        queue = Queue()
        # Spawn workers to process
        for t in range(num_threads):
            worker = cls(queue=queue, client=client, sink=sink)
            t = Thread(target=worker.process)
            t.daemon = True
            t.start()

         # Fill up the queue
        for import_spec in import_specs:
            queue.put(import_spec)

        # Wait for queue to be processed
        queue.join()

    def __init__(self, client, queue, sink):
        self._client = client
        self._queue = queue
        self._sink = sink

    def process(self):
        while True:
            import_spec = self._queue.get()
            logging.info("Importing {}".format(import_spec))
            try:
                releases = self._get_releases(import_spec)
                releases = map(self._serialize_release, releases)
                self._sink.put_releases(filter(None, releases))
            except SinkException:
                # can't really report this one
                msg = "Failed to import {}: {}".format(import_spec, e)
                logging.warn(msg)
            except (ValueError, KeyError, InvalidArchiveError) as e:
                msg = "Failed to import {}: {}".format(import_spec, e)
                logging.warn(msg)
                self._sink.post_error(msg, e)

            finally:
                self._queue.task_done()

    def _get_releases(self, import_spec):
        if import_spec.version:
            release = self._client.release(
                import_spec.package_name, import_spec.version)
            return [release] if release else []
        else:
            return self._client.releases(import_spec.package_name)

    def _serialize_release(self, release):
        try:
            return self._sink.serialize_release(release)
        except InvalidArchiveError as e:
            msg = "Failed to import {} {}: {}".format(
                release.package_name, release.version, e)
            logging.warn(msg)
            self._sink.post_error(msg, e)