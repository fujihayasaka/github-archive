## Local Development
### Installing Gem
1. Add the gem name to the `Gemfile`
2. Run `make install-gems`

### Updating Feature Flags Data Gem Version
1. Run `make install-gems` to download the gem
2. Run `gem list | grep "feature-flags-data"` and note the new version
3. In script/move-rbi change the data_version to the new version
4. Run `script/move-rbi` this will vendor the rbi files in the gem into vexi's sorbet directory
4. Run `make typecheck`
5. Run `make test`

### Sorbet Typechecking
1. run `make typecheck` to run sorbet
    - you can add autocorrect using `make typecheck FLAGS=-a`

### Vexi CLI
The CLI will be used for local testing to toggle feature flags. It allows for the usages defined below.
```
Usage: vexi enable|disable [options]
    -f, --flag=flag                  Add feature flag name
    -d, --directory=directory        Set the directory where you want to generate the file defaults to examples/generated
        --percentage_of_actors=percentage
                                     Add percentage of actors
        --percentage_of_calls=percentage
                                     Add percentage of calls
        --gate=gate_name             Add custom gates
        --actor=actor_id             Add actors using actor id format type:value
    -h, --help                       Prints this help
```
#### Usage
1. Run `make gem` to generate the ruby gem for the CLI
2. To enable a feature flag and set percentage of actors set to 56%, set percentage of calls to 45%, add custom gates `my_gate1` and `my_gate2`, and add actors `my_actor1` and `my_actor2`
```
vexi enable -f feature_flag_name --percentage_of_actors=56 --percentage_of_calls=45 --gate=my_gate1 --gate=my_gate2 --actor=my_actor1 --actor=my_actor2
```
3. To disable a feature flag
```
vexi disable -f feature_flag_name
```

