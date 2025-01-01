from httmock import urlmatch, all_requests, HTTMock
from pypi_client import PypiClient, Dependency, ReleaseLogEntry
from unittest.mock import patch
import os
import shutil
import xmlrpc



DATA_DIR = 'tmp/archives'


def setup_module(module):
    try:
        os.makedirs(DATA_DIR)
    except FileExistsError:
        pass


def teardown_module(module):
    shutil.rmtree(DATA_DIR)

@patch('xmlrpc.client.ServerProxy')
def test_packages_changed_since_no_changes(mock_server_proxy):
    mock_server_proxy.return_value.changelog_since_serial.return_value = []
    client = PypiClient(data_dir=DATA_DIR)
    serial = 100

    result, new_serial = client.packages_changed_since(serial)

    assert set() == result
    assert new_serial == serial

@patch('xmlrpc.client.ServerProxy')
def test_packages_changed_since_with_changes(mock_server_proxy):
    changes = [
        ['tight', '0.4.2', 1106371315, 'update home_page', 4385],
        ['head', '0.9.1', 1252306908, 'new release', 4388]
    ]
    mock_server_proxy.return_value.changelog_since_serial.return_value = changes
    client = PypiClient(data_dir=DATA_DIR)
    serial = 100

    result, new_serial = client.packages_changed_since(serial)

    expected_result = {
        ReleaseLogEntry(package_name='head', version='0.9.1')
    }
    expected_new_serial = 4388

    assert result == expected_result
    assert new_serial == expected_new_serial

def test_packages():
    with HTTMock(*api_mocks):
        client = PypiClient(data_dir=DATA_DIR)
        assert client.package_names() == [
            'airflow', 'jobmanager', 'numpy', 'pandas']


def test_releases():
    with HTTMock(*api_mocks):
        client = PypiClient(data_dir=DATA_DIR)
        releases = client.releases('tensorflow')
        assert len(releases) == 3
        assert sorted(list(map(lambda r: r.version, releases))) == [
            '0.12.1', '1.0.0', '1.0.1']

        releases = client.releases('jobmanager')
        assert len(releases) == 1
        assert sorted(list(map(lambda r: r.version, releases))) == [
            '0.1.0']


def test_release():
    with HTTMock(*api_mocks):
        r = release('tensorflow', '1.0.0')
        assert r.description == 'TensorFlow helps the tensors flow'
        assert r.authors == 'Google Inc.'
        assert r.download_count == 67
        assert not r.source_url
        assert r.home_url == 'https://www.tensorflow.org/'
        assert r.docs_url == 'https://www.tensorflow.org/api_docs'
        assert r.published_at == 1487137421

        client = PypiClient(data_dir=DATA_DIR)
        r = client.release('jobmanager', '0.1.0')
        assert r.description == 'Python job manager for parallel computing.'
        assert r.authors == 'Richard Hartmann'
        assert r.download_count == 1626
        assert r.source_url == 'https://github.com/cimatosa/jobmanager'
        assert r.home_url == 'https://github.com/cimatosa/jobmanager'
        assert not r.docs_url
        assert r.published_at == 1420564368


def test_wheel_dependencies():
    with HTTMock(*api_mocks):
        r = release('tensorflow', '1.0.0')
        deps = sorted(r.dependencies(), key=lambda d: d.package_name)
        assert len(deps) == 6
        assert deps == [
            Dependency(package_name='mock',
                       requirements='>= 2.0.0', runtime=True),
            Dependency(package_name='numpy',
                       requirements='>= 1.11.0', runtime=True),
            Dependency(package_name='protobuf',
                       requirements='>= 3.1.0', runtime=True),
            Dependency(package_name='scipy',
                       requirements='>= 0.15.1', runtime=False),
            Dependency(package_name='six',
                       requirements='>= 1.10.0', runtime=True),
            Dependency(package_name='wheel', requirements='', runtime=True),
        ]

        client = PypiClient(data_dir=DATA_DIR)
        r = client.release('pytest-mongodb', '2.1.1')
        deps = sorted(r.dependencies(), key=lambda d: d.package_name)
        assert len(deps) == 5

        assert deps == [
            Dependency(package_name='flake8',
                       requirements='>= 2.1.0', runtime=False),
            Dependency(package_name='mongomock',
                       requirements='', runtime=True),
            Dependency(package_name='pymongo', requirements='', runtime=True),
            Dependency(package_name='pytest',
                       requirements='>= 2.5.2', runtime=True),
            Dependency(package_name='pyyaml', requirements='', runtime=True),
        ]


def test_wheel_v1_dependencies():
    with HTTMock(*api_mocks):
        r = release('annotald', '1.1')
        deps = sorted(r.dependencies(), key=lambda d: d.package_name)
        assert len(deps) == 4
        assert deps == [
            Dependency(package_name='argparse',
                requirements='', runtime=True),
            Dependency(package_name='cherrypy',
                       requirements='', runtime=True),
            Dependency(package_name='mako',
                       requirements='', runtime=True),
            Dependency(package_name='nltk',
                       requirements='', runtime=True),
        ]


def test_egg_dependencies():
    with HTTMock(*api_mocks):
        client = PypiClient(data_dir=DATA_DIR)
        r = client.release('google-oauth', '1.0.0')
        deps = sorted(r.dependencies(), key=lambda d: d.package_name)
        assert len(deps) == 3
        assert deps == [
            Dependency(package_name='pyopenssl',
                       requirements='>= 0.11', runtime=True),
            Dependency(package_name='requests', requirements='', runtime=True),
            Dependency(package_name='six', requirements='', runtime=True),
        ]


def release(package_name, version):
    client = PypiClient(data_dir=DATA_DIR)
    releases = client.releases(package_name)
    return next(r for r in releases if r.version == version)


@urlmatch(netloc='pypi.python.org', path='/simple')
def simple_api_mock(url, request):
    return open('test/fixtures/simple.html').read()


@urlmatch(netloc='pypi.python.org', path='/pypi/tensorflow/json')
def tensorflow_json_mock(url, request):
    return open('test/fixtures/tensorflow.json').read()


@urlmatch(netloc='pypi.python.org', path='/packages/0d/d7/b49a6ceb055f392f91bce25eb6e1665f9b2f0a4628f7acdbccf1cd1d0ee6/tensorflow-1.0.0-cp27-cp27m-macosx_10_11_x86_64.whl')
def tensorflow_archive_mock(url, request):
    return open('test/fixtures/tensorflow-1.0.0-cp27-cp27m-macosx_10_11_x86_64.whl', 'rb').read()


@urlmatch(netloc='pypi.python.org', path='/pypi/jobmanager/json')
def jobmanager_json_mock(url, request):
    return open('test/fixtures/jobmanager.json').read()


@urlmatch(netloc='pypi.python.org', path='/pypi/google-oauth/json')
def google_oauth_json_mock(url, request):
    return open('test/fixtures/google-oauth.json').read()


@urlmatch(netloc='pypi.python.org', path='/packages/03/1a/60e91ec9c5576cd9f72626c6102785aaa6df4599cb9dc8abf4fc993ab9ac/google-oauth-1.0.0.tar.gz')
def google_oauth_archive_mock(url, request):
    return open('test/fixtures/google-oauth-1.0.0.tar.gz', 'rb').read()


@urlmatch(netloc='pypi.python.org', path='/pypi/pytest-mongodb/json')
def pytest_mongodb_json_mock(url, request):
    return open('test/fixtures/pytest-mongodb.json').read()


@urlmatch(netloc='pypi.python.org', path='/packages/f0/77/53af6e0e6922883d8395d06eebbb712a864c8d3b09e020bc6cf2e55af8f5/pytest-mongodb-2.1.1.tar.gz')
def pytest_mongodb_archive_mock(url, request):
    return open('test/fixtures/pytest-mongodb-2.1.1.tar.gz', 'rb').read()


@urlmatch(netloc='pypi.python.org', path='/packages/ad/ab/bf31de733982d190a3e566d28ecf9bc283ec335652a353a5b36920f6b0c9/pytest_mongodb-2.1.1-py2.py3-none-any.whl')
def pytest_mongodb_wheel_archive_mock(url, request):
    return open('test/fixtures/pytest_mongodb-2.1.1-py2.py3-none-any.whl', 'rb').read()


@urlmatch(netloc='pypi.python.org', path='/pypi/annotald/json')
def annotald_json_mock(url, request):
    return open('test/fixtures/annotald.json').read()


@urlmatch(netloc='pypi.python.org', path='/packages/47/3f/0788fe17f3825cc4372c54918acbc8dcbf546550cbec554cf8a665018238/annotald-1.1-py2.py3-none-any.whl')
def annotald_wheel_archive_mock(url, request):
    return open('test/fixtures/annotald-1.1-py2.py3-none-any.whl', 'rb').read()


api_mocks = [
    simple_api_mock,
    tensorflow_json_mock,
    tensorflow_archive_mock,
    jobmanager_json_mock,
    google_oauth_json_mock,
    google_oauth_archive_mock,
    pytest_mongodb_json_mock,
    pytest_mongodb_archive_mock,
    pytest_mongodb_wheel_archive_mock,
    annotald_json_mock,
    annotald_wheel_archive_mock,
]
