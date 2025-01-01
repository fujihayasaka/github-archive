require "rails_helper"

describe "Setup.py parsing" do
  let(:file) do
    <<~FILE
      from setuptools import setup, find_packages
      from os import path

      setup(
          name='example',
          version="0.4.5",
          description='A python project',
          author='hubot',
          author_email='hubot@aol.com',
          keywords=['ml', 'yaml'],
          license='MIT',
          install_requires=['pyyaml', 'tagpy'],
          tests_require=['mock', 'nose>=2.0.0'],
          classifiers=[
              'Programming Language :: Python',
              'Operating System :: OS Independent',
              'Environment :: Console',
          ],
          packages=find_packages('.'),
          url='http://example.org/',
      )
    FILE
  end

  let(:manifest) do
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "setup.py",
      path: "",
      content: file,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    })
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  specify { expect(manifest.package_manager).to eq Types::PackageManager[:pip] }
  specify { expect(manifest.manifest_type).to eq Types::Manifest[:setup_py] }
  specify { expect(manifest.dependent_name).to eq "example" }
  specify { expect(manifest.dependent_version).to eq "0.4.5" }
  specify { expect(manifest.filename).to eq "setup.py" }
  specify { expect(manifest.path).to eq "" }
  specify { expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest.pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest.github_repository_id).to eq 55 }
  specify { expect(manifest).to_not be_fork }
  specify { expect(manifest).to_not be_malformed }

  it "parses dependencies" do
    expect(manifest.dependencies).to match_array [
      dependency(package_name: "pyyaml", scope: :runtime, requirements:  "", raw_requirements: ""),
      dependency(package_name: "tagpy", scope: :runtime, requirements:  "", raw_requirements: ""),
      dependency(package_name: "mock", scope: :development, requirements:  "", raw_requirements: ""),
      dependency(package_name: "nose", scope: :development, requirements:  ">= 2.0.0", raw_requirements: ">= 2.0.0"),
    ]
  end

  context "setup.py with variable" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        REQUIRED_PACKAGES = [
            'absl-py >= 0.1.6',
            'astor >= 0.6.0',
            'gast >= 0.2.0',
            'grpcio >= 1.8.6',
            'numpy >= 1.13.3',
            'six >= 1.10.0',
            'protobuf >= 3.4.0',
            'tensorboard >= 1.6.0, < 1.7.0',
            'termcolor >= 1.1.0',
        ]

        REQUIRES = ['pyyaml', 'tagpy']

        setup(
            name='example',
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            keywords=['ml', 'yaml'],
            license='MIT',
            install_requires=REQUIRED_PACKAGES,
            classifiers=[
                'Programming Language :: Python',
                'Operating System :: OS Independent',
                'Environment :: Console',
            ],
            packages=find_packages('.'),
            url='http://example.org/',
        )
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "absl-py", scope: :runtime, requirements: ">= 0.1.6", raw_requirements: ">= 0.1.6"),
        dependency(package_name: "astor", scope: :runtime, requirements: ">= 0.6.0", raw_requirements: ">= 0.6.0"),
        dependency(package_name: "gast", scope: :runtime, requirements: ">= 0.2.0", raw_requirements: ">= 0.2.0"),
        dependency(package_name: "grpcio", scope: :runtime, requirements: ">= 1.8.6", raw_requirements: ">= 1.8.6"),
        dependency(package_name: "numpy", scope: :runtime, requirements: ">= 1.13.3", raw_requirements: ">= 1.13.3"),
        dependency(package_name: "six", scope: :runtime, requirements: ">= 1.10.0", raw_requirements: ">= 1.10.0"),
        dependency(package_name: "protobuf", scope: :runtime, requirements: ">= 3.4.0", raw_requirements: ">= 3.4.0"),
        dependency(package_name: "tensorboard", scope: :runtime, requirements: ">= 1.6.0,< 1.7.0", raw_requirements: ">= 1.6.0,< 1.7.0"),
        dependency(package_name: "termcolor", scope: :runtime, requirements: ">= 1.1.0", raw_requirements: ">= 1.1.0"),
      ]
    end
  end

  context "setup.py with kwargs" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        metadata = dict(
            name='example',
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            keywords=['ml', 'yaml'],
            license='MIT',
            install_requires=['numpy', 'scipy'],
            classifiers=[
                'Programming Language :: Python',
                'Operating System :: OS Independent',
                'Environment :: Console',
            ],
            packages=find_packages('.'),
            url='http://example.org/',
        )

        setup(**metadata)
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "numpy", scope: :runtime, requirements:  "", raw_requirements:  ""),
        dependency(package_name: "scipy", scope: :runtime, requirements:  "", raw_requirements:  ""),
      ]
    end
  end

  context "setup.py with kwargs dict literal" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        metadata = {
            'name': 'example',
            'version': '0.4.5',
            'description': 'A python project',
            'author': 'hubot',
            'author_email': 'hubot@aol.com',
            'keywords': ['ml', 'yaml'],
            'license': 'MIT',
            'install_requires': ['numpy', 'scipy'],
            'classifiers': [
                'Programming Language :: Python',
                'Operating System :: OS Independent',
                'Environment :: Console',
            ],
            'packages': find_packages('.'),
            'url': 'http://example.org/',
        }

        setup(**metadata)
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "numpy", scope: :runtime, requirements:  "", raw_requirements:  ""),
        dependency(package_name: "scipy", scope: :runtime, requirements:  "", raw_requirements:  ""),
      ]
    end
  end

  context "setup.py with a string" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        metadata = dict(
            name='example',
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            keywords=['ml', 'yaml'],
            license='MIT',
            install_requires='''
              numpy
              scipy==1.2.0
              ''',
            classifiers=[
                'Programming Language :: Python',
                'Operating System :: OS Independent',
                'Environment :: Console',
            ],
            packages=find_packages('.'),
            url='http://example.org/',
        )

        setup(**metadata)
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "numpy", scope: :runtime, requirements:  "", raw_requirements:  ""),
        dependency(package_name: "scipy", scope: :runtime, requirements:  "= 1.2.0", raw_requirements:  "= 1.2.0"),
      ]
    end
  end

  context "setup.py with a string tuple" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        metadata = dict(
            name='example',
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            keywords=['ml', 'yaml'],
            license='MIT',
            install_requires=(
                'python-dateutil>=2.1',
                'six>=1.4.1',
                'rfc3987',
            ),
            classifiers=[
                'Programming Language :: Python',
                'Operating System :: OS Independent',
                'Environment :: Console',
            ],
            packages=find_packages('.'),
            url='http://example.org/',
        )

        setup(**metadata)
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "python-dateutil", scope: :runtime, requirements:  ">= 2.1", raw_requirements:  ">= 2.1"),
        dependency(package_name: "six", scope: :runtime, requirements:  ">= 1.4.1", raw_requirements:  ">= 1.4.1"),
        dependency(package_name: "rfc3987", scope: :runtime, requirements:  "", raw_requirements:  ""),
      ]
    end
  end

  context "setup.py with programmatically-generated requirements" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        setup(
            name='example',
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            license='MIT',
            install_requires=_some_function(),
            packages=find_packages('.'),
            url='http://example.org/',
        )
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array []
    end
  end

  context "setup.py with programmatically-generated args" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        setup(_some_function())
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array []
    end
  end

  context "setup.py with programmatically-generated kwargs" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        metadata = _some_function()

        setup(**metadata)
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array []
    end
  end

  context "setup.py with variable package name and version" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        PACKAGE_NAME = 'numpy'
        VERSION = '0.2.1'

        setup(
          name=PACKAGE_NAME,
          version=VERSION,
        )
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependent_name).to eq "numpy"
      expect(manifest.dependent_version).to eq "0.2.1"
    end
  end

  context "setup.py with an absent variable" do
    let(:file) do
      <<~FILE
        from setuptools import setup, find_packages
        from os import path

        setup(
            name='example', # A comment
            version='0.4.5',
            description='A python project',
            author='hubot',
            author_email='hubot@aol.com',
            license='MIT',
            install_requires=REQUIRED_PACKAGES,
            packages=find_packages('.'),
            url='http://example.org/',
        )
      FILE
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array []
    end
  end

  context "setup.py with a null byte" do
    let(:file) do
      "Hello\u0000"
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array []
    end
  end
end
