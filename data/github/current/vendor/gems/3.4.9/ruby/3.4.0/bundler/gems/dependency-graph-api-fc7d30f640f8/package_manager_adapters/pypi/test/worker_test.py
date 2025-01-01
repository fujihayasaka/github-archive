import pytest
from worker import Worker, ImportSpec


@pytest.fixture
def client():
    return FakePypiClient({
        'tensorflow': {
            '1.1.0': 'tensorflow-1.1.0',
            '1.1.1': 'tensorflow-1.1.1',
        }
    })


def test_importing_all_releases(client):
    sink = FakeSink()
    import_specs = [ImportSpec(package_name='tensorflow', version=None)]
    Worker.process_specs(import_specs=import_specs, client=client, sink=sink, num_threads=1)

    assert sorted(sink.releases) == ['tensorflow-1.1.0', 'tensorflow-1.1.1']


def test_importing_a_single_release(client):
    sink = FakeSink()
    import_specs = [ImportSpec(package_name='tensorflow', version='1.1.1')]
    Worker.process_specs(import_specs=import_specs, client=client, sink=sink, num_threads=1)

    assert sorted(sink.releases) == ['tensorflow-1.1.1']


def test_importing_a_missing_release(client):
    sink = FakeSink()
    import_specs = [ImportSpec(package_name='tensorflow', version='1.1.2')]
    Worker.process_specs(import_specs=import_specs, client=client, sink=sink, num_threads=1)

    assert sorted(sink.releases) == []


class FakeSink:
    def __init__(self):
        self.releases = []

    def serialize_release(self, release):
        return release

    def put_releases(self, releases):
        self.releases += releases


class FakePypiClient:
    def __init__(self, releases):
        self._releases = releases

    def releases(self, package_name):
        return self._releases.get(package_name, {}).values()

    def release(self, package_name, version):
        return self._releases.get(package_name, {}).get(version)
