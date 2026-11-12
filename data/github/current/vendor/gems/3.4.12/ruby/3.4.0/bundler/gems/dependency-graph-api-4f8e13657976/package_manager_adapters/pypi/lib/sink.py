import requests
import json
import traceback
import logging

CHECKPOINT = 'pypi'


class SinkException(Exception):
    pass


class Sink:
    def __init__(self, sink_proxy_url):
        self.url = sink_proxy_url

    def put_releases(self, releases):
        url = '{}/package_releases'.format(self.url)
        request = requests.post(
            url, data={'package_releases': json.dumps(list(releases))})

        if not request.ok:
            logging.critical("Error in Sink#put_releases: {}".format(request.text))
            self._handle_failed_request(request)

    def checkpoint(self):
        url = '{}/checkpoints/{}'.format(self.url, CHECKPOINT)
        request = requests.get(url)

        if not request.ok:
            logging.critical("Error in Sink#checkpoint: {}".format(request.text))
            self._handle_failed_request(request)

        return json.loads(request.content.decode('utf-8'))['value']

    def put_checkpoint(self, value):
        url = '{}/checkpoints/{}'.format(self.url, CHECKPOINT)
        request = requests.put(url, data={'value': value})

        if not request.ok:
            logging.critical("Error in Sink#put_checkpoint: {}".format(request.text))
            self._handle_failed_request(request)

    def post_error(self, message, exception):
        url = '{}/errors'.format(self.url)
        backtrace = "".join(traceback.format_exception(type(exception), exception ,exception.__traceback__))
        request = requests.post(url, data={'message': message, 'backtrace': backtrace})

        if not request.ok:
            logging.critical("Error in Sink#post_error: {}".format(request.text))
            self._handle_failed_request(request)

    def _handle_failed_request(self, request):
        raise SinkException(request.text)

    def serialize_release(self, release):
        dependencies = map(self._serialize_dependency, release.dependencies())

        return {
            'package_manager': 'pip',
            'package_name': release.package_name,
            'version': release.version,
            'description': release.description,
            'authors': release.authors,
            'download_count': release.download_count,
            'source_url': release.source_url,
            'home_url': release.home_url,
            'docs_url': release.docs_url,
            'published_at': release.published_at,
            'dependencies':  list(dependencies),
        }

    def _serialize_dependency(self, dependency):
        scope = 'runtime' if dependency.runtime else 'development'

        return {
            'package_name': dependency.package_name,
            'requirements': dependency.requirements,
            'scope': scope,
        }
