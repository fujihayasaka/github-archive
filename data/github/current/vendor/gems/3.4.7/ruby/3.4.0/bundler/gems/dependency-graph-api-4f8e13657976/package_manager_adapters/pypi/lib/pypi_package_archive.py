import json
import re
import os
import zipfile
import tarfile


ZIP_EXTENSIONS = ('egg', '.zip', '.whl')
TAR_EXTENSIONS = ('.tar.gz', '.tgz', '.tar', 'tar.bz2')
WHEEL_EXTENSION = ('.whl')


class InvalidArchiveError(Exception):
    pass


class PypiPackageArchive:
    """
    Archive abstracts over the egg and wheel PyPI archive formats. It downloads
    and extracts dependency metadata from archive files, and then cleans up.
    """

    def __init__(self, archive_file):
        self.archive_file = archive_file

    def dependencies(self):
        if self.archive_file.lower().endswith(WHEEL_EXTENSION):
            dependencies = self._wheel_dependencies()
        else:
            dependencies = self._egg_dependencies()

        return dependencies

    def _reader(self):
        if not self.archive_file.lower().endswith(ZIP_EXTENSIONS + TAR_EXTENSIONS):
            raise InvalidArchiveError(
                'unrecognized archive format {}'.format(self.archive_file))

        if self.archive_file.lower().endswith(ZIP_EXTENSIONS):
            return ZipfileReader(self.archive_file)
        elif self.archive_file.lower().endswith(TAR_EXTENSIONS):
            return TarfileReader(self.archive_file)

    def _wheel_dependencies(self):
        try:
            metadata = list(sorted(filter(
                re.compile(r'dist-info/metadata(.json)?$', re.IGNORECASE).search,
                self._reader().namelist()), reverse=True))[0]

            contents = self._reader().read(metadata).decode('utf-8')

            if metadata.endswith('json'):
                metadata = MetadataJson(contents)
            else:
                metadata = MetadataTxt(contents)
        except (IndexError, ValueError):
            raise InvalidArchiveError(
                'Invalid wheel archive {}'.format(self.archive_file))

        return {
            'runtime': metadata.runtime_dependencies(),
            'test': metadata.test_dependencies(),
        }

    def _egg_dependencies(self):
        files = filter(re.compile(r'egg-info/(setup_)?requires.txt$').search,
                       self._reader().namelist())

        runtime, test = [], []
        for f in files:
            _file = RequiresTxt(self._reader().read(f).decode('utf-8'))
            runtime += _file.runtime_dependencies()
            test += _file.test_dependencies()

        return {'runtime': runtime, 'test': test}


class ZipfileReader:
    def __init__(self, filename):
        zipfp = open(filename, 'rb')
        self.archive = zipfile.ZipFile(zipfp, allowZip64=True)

    def namelist(self):
        return self.archive.namelist()

    def read(self, filename):
        return self.archive.read(filename)


class RequiresTxt:
    def __init__(self, contents):
        self.contents = contents.splitlines()

    def runtime_dependencies(self):
        return list(filter(self._filter_line, self.contents))

    def test_dependencies(self): return []

    def _filter_line(self, line):
        if line.strip() and not line.startswith('['):
            return line


class TarfileReader:
    def __init__(self, filename):
        self.archive = tarfile.open(filename, 'r')

    def namelist(self):
        return [t.name for t in self.archive.getmembers()]

    def read(self, filename):
        return self.archive.extractfile(filename).read()


class MetadataJson:
    def __init__(self, contents):
        self._metadata = json.loads(contents)

    def runtime_dependencies(self):
        try:
            return self._metadata['run_requires'][0]['requires']
        except KeyError:
            return []

    def test_dependencies(self):
        try:
            return self._metadata['test_requires'][0]['requires']
        except KeyError:
            return []

class MetadataTxt:
    def __init__(self, contents):
        self.contents = contents

    def runtime_dependencies(self):
        return re.findall(r'Requires-Dist: (.+)', self.contents)

    def test_dependencies(self):
        return []
