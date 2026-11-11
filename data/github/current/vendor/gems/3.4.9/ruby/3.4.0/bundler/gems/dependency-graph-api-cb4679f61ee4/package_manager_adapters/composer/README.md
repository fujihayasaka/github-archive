## The composer package manager adapter

### Running the adapter

Run the adapter with `package_manager_adapters/script/start composer`

### Running the tests

Run adapter tests with `package_manager_adapters/script/test composer`

### Prepare for deploy

The composer package manager adapter has a dependency on `nokogiri` which includes prebuild libraries for multiple platforms.  When the gems are cached on a MacOS machine, the libraries are different from those needed on production servers.  The following is required to ensure that the library required for production is available as part of the cache that is used when building `/Dockerfile`.

```sh
cd package_manager_adapters/composer
bundle cache
bundle lock --add-platform x86_64-linux
bundle package --all-platforms
```
