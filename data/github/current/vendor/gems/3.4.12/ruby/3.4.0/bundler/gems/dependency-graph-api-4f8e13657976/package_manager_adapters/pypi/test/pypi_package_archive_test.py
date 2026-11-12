from pypi_package_archive import RequiresTxt, MetadataJson


def test_requires_txt():
    requires_txt = RequiresTxt("""
emoji
termcolor2

[markdown]
Markdown>=1.1.0

[mongodb]
pymongo
asyncio_mongo
    """)

    assert requires_txt.runtime_dependencies() == [
        'emoji',
        'termcolor2',
        'Markdown>=1.1.0',
        'pymongo',
        'asyncio_mongo',
    ]

    assert requires_txt.test_dependencies() == []


def test_metadata_json():
    metadata = MetadataJson("""
{
  "classifiers": ["Topic :: Scientific/Engineering"],
  "description_content_type": "UNKNOWN",
  "extensions": {},
  "extras": [],
  "license": "BSD",
  "metadata_version": "2.0",
  "name": "pandas",
  "platform": "any",
  "run_requires": [
    {
      "requires": [
        "numpy (>=1.9.0)",
        "python-dateutil",
        "pytz (>=2011k)"
      ]
    }
  ],
  "test_requires": [
    {
      "requires": [
        "mock"
      ]
    }
  ],
  "summary": "Powerful data structures for data analysis, time series,and statistics",
  "version": "0.21"
}
    """)

    assert metadata.runtime_dependencies() == [
        'numpy (>=1.9.0)',
        'python-dateutil',
        'pytz (>=2011k)',
    ]

    assert metadata.test_dependencies() == ['mock']

    metadata = MetadataJson("""
{
  "classifiers": ["Topic :: Scientific/Engineering"],
  "description_content_type": "UNKNOWN",
  "extensions": {},
  "extras": [],
  "license": "BSD",
  "metadata_version": "2.0",
  "name": "pandas",
  "platform": "any",
  "summary": "Powerful data structures for data analysis, time series,and statistics",
  "version": "0.21"
}
    """)

    assert metadata.runtime_dependencies() == []

    assert metadata.test_dependencies() == []
