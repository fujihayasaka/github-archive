const path = require('path')
const root = path.join(__dirname, '/../')
const Package = require(root + 'lib/package')
const PackageRelease = require(root + 'lib/package_release')

const couchDBRecord = {
  _id: 'left-pad',
  name: 'left-pad',
  description: 'String left pad',
  homepage: 'http://left-pad.com',
  time: {
    modified: '2017-06-14T13:20:37.027Z',
    created: '2014-03-14T09:09:20.762Z',
    '1.1.3': '2016-10-01T08:01:07.703Z'
  },
  repository: {
    type: 'git',
    url: 'git://github.com/stevemao/left-pad.git'
  },
  versions: {
    '1.1.3': {
      name: 'left-pad',
      version: '1.1.3',
      scripts: {'test': 'node test'},
      keywords: ['left', 'pad'],
      main: 'index.js',
      author: {name: 'azer'},
      description: 'String left pad',
      licenses: [
        {"type": 'MIT', "url": "https://example.com"},
        {"type": "Apache-2.0", "url": "https://moar.example.com"}
      ],
      dependencies: {
        ids: '^0.2.0',
        inherits: '^2.0.1',
        lodash: '^3.0.1'
      },
      devDependencies: {
        sinon: '~1.14.1',
        'sinon-chai': '~2.7.0'
      },
      gitHead: '0e77bae522b79d3e5cf83f07c460c486a68d0f36',
      maintainers: [
        {
          name: 'a maintainer',
          email: 'email@example.com'
        }
      ],
      dist: {
        shasum: '0dc4510ada884f29a793de2bd06eb529ee44e5eb',
        tarball: 'http://registry.npmjs.org/1.1.3.tgz'
      }
    }
  }
}

const packageJson = {
  'name': 'my-lib',
  'version': '1.1.0',
  'description': 'A useful library',
  'main': 'index.js',
  'keywords': [],
  'author': 'mona',
  'license': 'UNLICENSED',
  'scripts': {},
  'dependencies': {
    'express': '4.15.3',
    'socket.io': '2.0.3'
  },
  'devDependencies': {
    'gulp': '^3.9.1'
  }
}

module.exports = {
  validPackage: new Package(couchDBRecord, 10),
  invalidPackage: new Package({
    _id: null,
    name: null,
    version: null,
    description: 'This package is missing metadata',
    time: {},
    repository: {},
    versions: {
      '4.15.2': {}
    }
  }, 20),

  // for license extraction unit tests
  testReleasesWithLicense: [
    {
      release: new PackageRelease(null, {
        license: "MIT",
      }),
      expected: "MIT",
    },
    {
      release: new PackageRelease(null, {
        license: { type: "EliCorp-1.0", url: "https://example.com/MIT" },
      }),
      expected: "EliCorp-1.0",
    },
    {
      release: new PackageRelease(null, {
        license: "BSD-3-Clause AND (Apache-2.0 OR MIT)",
      }),
      expected: "BSD-3-Clause AND (Apache-2.0 OR MIT)",
    },
    {
      release: new PackageRelease(null, {
        license: "",
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        license: []
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        license: {},
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        license: null
      }),
      expected: "",
    }
  ],

  testReleasesWithLicenses: [
    {
      release: new PackageRelease(null, {
        licenses: [
           { type: "MIT", url: "https://example.com/MIT" },
           { type: "Apache-2.0", url: "https://example.com/Apache-2.0" }
         ]
      }),
      expected: "MIT OR Apache-2.0",
    },
    {
      release: new PackageRelease(null, {
        licenses: [null, null],
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        licenses: [],
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        licenses: {}
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        licenses: "",
      }),
      expected: "",
    },
    {
      release: new PackageRelease(null, {
        licenses: null
      }),
      expected: "",
    }
  ]
}
