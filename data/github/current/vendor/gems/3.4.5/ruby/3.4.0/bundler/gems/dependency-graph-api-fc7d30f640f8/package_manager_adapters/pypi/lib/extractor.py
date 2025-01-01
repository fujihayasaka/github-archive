import os
import sys
import logging
from pypi_client import PypiClient
from sink import Sink, SinkException
from worker import Worker, ImportSpec

DATA_DIR = os.environ['DATA_DIR']
SINK_PROXY_URL = os.environ.get('SINK_PROXY_URL', 'http://localhost:7777')
LOGGING_FORMAT = 'now="%(asctime)-15s" package_manager=pypi log_message="%(message)s"'

logging.basicConfig(level=logging.INFO, format=LOGGING_FORMAT)

def update(num_threads=20):
    """
    Sync all releases from PyPI that were published since the last sync.
    """
    sink = Sink(sink_proxy_url=SINK_PROXY_URL)
    old_checkpoint = sink.checkpoint()
    client = PypiClient(data_dir=DATA_DIR)

    changes, new_checkpoint = client.packages_changed_since(old_checkpoint)
    import_specs = map(_changelog_entry_to_import_spec, changes)

    _import_packages(import_specs=import_specs, num_threads=num_threads, sink=sink, client=client)

    Sink(sink_proxy_url=SINK_PROXY_URL).put_checkpoint(new_checkpoint)

def backfill(num_threads=100):
    """
    Backfill all releases from PyPI. This process is relatively slow because it
    downloads and extracts all release archive files. Once backfilled, we can
    update data incrementally with update().
    """
    sink = Sink(sink_proxy_url=SINK_PROXY_URL)
    client = PypiClient(data_dir=DATA_DIR)

    new_checkpoint = client.changelog_last_serial()
    package_names = client.package_names()

    import_specs = map(_package_name_to_import_spec, package_names)

    _import_packages(import_specs=import_specs, num_threads=num_threads, sink=sink, client=client)

    Sink(sink_proxy_url=SINK_PROXY_URL).put_checkpoint(new_checkpoint)

def _package_name_to_import_spec(package_name):
    return ImportSpec(package_name=package_name, version=None)

def _changelog_entry_to_import_spec(entry):
    return ImportSpec(package_name=entry.package_name, version=entry.version)

def _import_packages(num_threads, import_specs, sink, client):
    Worker.process_specs(import_specs=import_specs, client=client, sink=sink, num_threads=num_threads)

if __name__ == "__main__":
    try:
        if '--backfill' in sys.argv[1:]:
            backfill()
        else:
            update()
    except SinkException:
        raise
    except Exception as e:
        sink = Sink(sink_proxy_url=SINK_PROXY_URL)
        sink.post_error("Unknown exception", e)
        raise
