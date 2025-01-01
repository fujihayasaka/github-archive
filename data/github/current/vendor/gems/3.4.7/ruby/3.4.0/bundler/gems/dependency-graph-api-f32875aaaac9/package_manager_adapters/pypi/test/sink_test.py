import pytest
import json
from operator import itemgetter
from urllib.parse import parse_qs
from functools import partial
from httmock import urlmatch, all_requests, HTTMock
from pypi_client import Release
from sink import Sink


def test_releases():
    releases = []
    with HTTMock(partial(package_releases_mock, releases)):
        sink = Sink(sink_proxy_url='http://localhost')
        release = Release(
            package_name='tensorflow',
            version='1.0.1',
            description='TensorFlow helps the tensors flow',
            authors='Google Inc.',
            download_count=1050,
            home_url='https://www.tensorflow.org/',
            docs_url='https://www.tensorflow.org/api_docs',
            published_at=1522086390,
            runtime_dependencies=['numpy >=1.11.0', 'protobuf'],
            test_dependencies=['mock >= 2.0.0'],
        )
        sink.put_releases([sink.serialize_release(release)])

        expected = [{
            'package_manager': 'pip',
            'package_name': 'tensorflow',
            'version': '1.0.1',
            'description': 'TensorFlow helps the tensors flow',
            'authors': 'Google Inc.',
            'download_count': 1050,
            'source_url': None,
            'home_url': 'https://www.tensorflow.org/',
            'docs_url': 'https://www.tensorflow.org/api_docs',
            'published_at': 1522086390,
            'dependencies': [
                {
                    'package_name': 'mock',
                    'requirements': '>= 2.0.0',
                    'scope': 'development',
                },
                {
                    'package_name': 'numpy',
                    'requirements': '>= 1.11.0',
                    'scope': 'runtime',
                },
                {
                    'package_name': 'protobuf',
                    'requirements': '',
                    'scope': 'runtime',
                },
            ],
        }]

        for key in expected[0]:
            assert releases[0][key] == expected[0][key]


def test_checkpoints():
    with HTTMock(partial(checkpoints_mock, {'value': 0})):
        sink = Sink(sink_proxy_url='http://localhost')
        assert sink.checkpoint() == 0
        sink.put_checkpoint(10)
        assert sink.checkpoint() == 10


@urlmatch(netloc='localhost', path='/checkpoints/pypi')
def checkpoints_mock(checkpoint, url, request):
    if request.method == 'PUT':
        checkpoint['value'] = int(parse_qs(request.body)['value'][0])
        return 'ok'
    else:
        return json.dumps(checkpoint)


@urlmatch(netloc='localhost', path='/package_releases')
def package_releases_mock(releases, url, request):
    data = json.loads(parse_qs(request.body)['package_releases'][0])
    for release in data:
        release['dependencies'] = sorted(
            release['dependencies'], key=itemgetter('package_name'))
        releases.append(release)

    return 'ok'
