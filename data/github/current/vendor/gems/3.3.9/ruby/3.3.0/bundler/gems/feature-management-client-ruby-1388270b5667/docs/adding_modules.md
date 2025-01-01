## Adding a New Module to the Library

Modules are added as folders off of the `lib` folder. The current design of this repo is that each module gets its own folder in the `lib` directory: e.g. `vexi` and `vexi_management`.

To create a new module you will need to do the following:

- Create a `<module_name>.gemspec` file in the root of the repo
- Create a new folder matching the `<module_name>` under `/lib`. The gemspec filename and the name of the directory need to match as this is used in our gem building / publishing scripts
- Make sure to include a `version.rb` file somewhere in the module path as this is used by the release processes
- Add a new entry for the module to the `release-please-config.json` file
- Add a placeholder entry for the module to the `.release-please-manifest.json` file
- Examples on using the module should be added to the `examples` folder

Once the module has been built and tested and we are ready to release, we should follow the `release-as` semantics to generate the initial release of the library, likely releasing as version `0.1.0` as a first test version. [Example PR](https://github.com/github/vexi-ruby/pull/51).
