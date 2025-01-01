from typing import Set, NamedTuple, Tuple
import json
import os
import re
import logging
from functools import reduce, lru_cache
from urllib.parse import urlparse
from collections import namedtuple
import xmlrpc.client as xmlrpclib

from dateutil import parser

from lxml import html
import requests
from pypi_package_archive import PypiPackageArchive
from requirements import normalize_requirement_set


class ReleaseLogEntry(NamedTuple):
    package_name: str
    version: str

class PypiClient:
    def __init__(self, data_dir):
        self.data_dir = data_dir

    def package_names(self):
        """
        Return a list of package names in the PyPI index.
        """
        request = requests.get('https://pypi.python.org/simple')

        if not request.ok:
            raise RuntimeError("Failed to download PyPI package list")

        tree = html.fromstring(request.content)
        return tree.xpath('//a/text()')

    def releases(self, package_name):
        """
        Return a list of all Release instanes for a given package.
        """
        data = self._fetch_releases(package_name)

        def collect_releases(out, version):
            release = self._build_release(data, version)
            if release:
                out.append(release)
            return out

        return reduce(collect_releases, data['releases'], [])

    def packages_changed_since(self, serial: int) -> Tuple[Set[ReleaseLogEntry], int]:
        """
        Retrieves the packages that have changed after `serial`.

        Args:
            serial (int): Start processing packages after (and including) this serial number.

        Returns:
            set[ReleaseLogEntry], new_serial: The set of changed release entries along with the new serial number.
        """
        new_serial = serial
        client = xmlrpclib.ServerProxy('https://pypi.python.org/pypi')
        changes = client.changelog_since_serial(serial)

        # Changelog entries format:
        # package_name, version, timestamp,     event,              serial
        # ['kid',       '0.4.2', 1106371315,    'update home_page', 4385]
        # ['idavoll',   '0.9.1', 1252306908,    'new release',      4388]

        releases = list(filter(lambda entry: entry and entry[3] == 'new release', changes))

        if len(releases) <= 0:
            return set(), serial

        new_serial = releases[-1][4]
        return set(map(lambda entry: ReleaseLogEntry(package_name=entry[0], version=entry[1]), releases)), new_serial

    def release(self, package_name, version):
        """
        Return a Release instance for a given package and version.
        """
        data = self._fetch_releases(package_name)
        return self._build_release(data, version)

    def changelog_last_serial(self):
        client = xmlrpclib.ServerProxy('https://pypi.python.org/pypi')
        return client.changelog_last_serial()

    def _fetch_releases(self, package_name):
        url = 'https://pypi.python.org/pypi/{}/json'.format(package_name)
        request = requests.get(url)

        if not request.ok:
            logging.error("No JSON API data {}".format(package_name))
            return {'releases': {}}

        try:
            return json.loads(request.content.decode('utf-8'))
        except json.decoder.JSONDecodeError:
            logging.error("Invalid JSON for package {}".format(package_name))
            return {'releases': {}}

    def _build_release(self, data, version):
        formats = data['releases'].get(version, [])

        if len(formats) == 0:
            return

        def dist_preference(dist):
            """
            When releases are published in multiple archive formats, we prefer
            wheels but fall back to eggs. We throw away Windows archives, so
            those get the lowest preference.
            """
            if dist['packagetype'].endswith('wheel'):
                return 0
            elif dist['filename'].endswith('zip'):
                return 1
            elif 'win' in dist['packagetype']:
                return 10
            else:
                return 5

        attributes = sorted(formats, key=dist_preference)[0]
        dependencies = LazyDependencies(
            archive_url=attributes['url'], data_dir=self.data_dir)

        return Release(
            package_name=data['info']['name'],
            version=version,
            description=data['info']['summary'],
            authors=data['info']['author'],
            download_count=attributes['downloads'],
            home_url=data['info']['home_page'],
            docs_url=data['info']['docs_url'],
            runtime_dependencies=dependencies.runtime_dependencies(),
            test_dependencies=dependencies.test_dependencies(),
            published_at=parser.parse(
                attributes['upload_time'] + " UTC").timestamp(),
        )

class LazyDependencies:
    """
    Lazily extracts dependencies from an archive so that Index can instantiate
    Releases without downloading and opening archive files unless absolutely
    necessary.
    """

    def __init__(self, archive_url, data_dir):
        self._archive_url = archive_url
        self._archive_file = os.path.join(
            data_dir, os.path.basename(urlparse(archive_url).path))

    """
    A generator for raw runtime dependency strings
    e.g. 'numpy' or 'numpy>=1.0.0'
    """

    def runtime_dependencies(self):
        for dependency in self._dependencies()['runtime']:
            yield(dependency)

    """
    A generator for raw test dependency strings
    e.g. 'mock' or 'mock==1.0.0'
    """

    def test_dependencies(self):
        for dependency in self._dependencies()['test']:
            yield(dependency)

    @lru_cache(maxsize=None)
    def _dependencies(self):
        self._download_file()
        dependencies = PypiPackageArchive(
            archive_file=self._archive_file).dependencies()
        os.remove(self._archive_file)

        return dependencies

    def _download_file(self):
        if not os.path.exists(self._archive_file):
            os.makedirs(os.path.dirname(self._archive_file), exist_ok=True)

        r = requests.get(self._archive_url, stream=True)
        with open(self._archive_file, 'wb') as f:
            for chunk in r.iter_content(chunk_size=1024):
                if chunk:
                    f.write(chunk)
                    f.flush()


class Release:
    """
    A PyPI package release.
    """

    def __init__(self, package_name, version, runtime_dependencies, test_dependencies, description=None,
                 authors=None, download_count=None, published_at=None, source_url=None,
                 home_url=None, docs_url=None):
        self.package_name = package_name
        self.version = version
        self.description = description
        self.authors = authors
        self.download_count = download_count
        self._source_url = source_url
        self.home_url = home_url
        self.docs_url = docs_url
        self.published_at = published_at
        self._test_dependencies = test_dependencies
        self._runtime_dependencies = runtime_dependencies

    @property
    def source_url(self):
        if not self._source_url:
            if self._url_on_github(self.home_url):
                return self.home_url
            if self._url_on_github(self.docs_url):
                return self.docs_url
        else:
            return self._source_url

    @lru_cache(maxsize=None)
    def dependencies(self):
        out = dict()

        for dependency in self._test_dependencies:
            dependency = self._parse_dependency(dependency, runtime=False)
            out[dependency.package_name] = dependency

        for dependency in self._runtime_dependencies:
            dependency = self._parse_dependency(dependency, runtime=True)
            out[dependency.package_name] = dependency

        return list(out.values())

    def _parse_dependency(self, dependency, runtime):
        values = re.search(r'([\w-]+)\s*\(?([^\)]*)', dependency)

        return Dependency(
            package_name=values.group(1),
            requirements=normalize_requirement_set(values.group(2)),
            runtime=runtime,
        )

    def _url_on_github(self, url):
        if not self.home_url:
            return False
        return urlparse(self.home_url).netloc == 'github.com'


Dependency = namedtuple(
    'Dependency', ['package_name', 'requirements', 'runtime'])
