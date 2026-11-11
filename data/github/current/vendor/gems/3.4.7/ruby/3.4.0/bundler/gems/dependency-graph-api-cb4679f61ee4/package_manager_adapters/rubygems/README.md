## rubygems package manager adapter

The rubygems package manager adapter downloads a weekly [postgres data dump](https://rubygems.org/pages/data) from [rubygems.org](https://rubygems.org), loads the dump into a local db and extracts package release data.

### Running the adapter

Run the adapter with `package_manager_adapters/script/start rubygems`

### Running the tests

Run adapter tests with `package_manager_adapters/script/test rubygems`
