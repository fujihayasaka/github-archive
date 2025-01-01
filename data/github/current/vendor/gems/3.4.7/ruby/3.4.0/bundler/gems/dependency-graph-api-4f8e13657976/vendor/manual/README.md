# Manually Vendoring spokes-proto

This process is necessary if you want to update the spokes-proto gem, at least for now.
It's not too difficult, it just has a bunch of steps.

### 1. Clone spokes-proto

Clone the spokes-proto repo with `gh repo clone github/spokes-proto`

### 2. Build the spokes-proto gem

Change to the spokes-proto/gen/ruby directory and run this command:

```
gem build spokes-proto.gemspec
```

This will create a file named `spokes-proto-<version>.gem`.

### 3. Unpack the gem to `vendor/manual`

Run the following command to unpack the gem:

```
gem unpack spokes-proto-<version>.gem -d /workspaces/dependency-graph-api/vendor/manual
```

(Note: that's assuming you're in a Codespace. Adjust the path if necessary.)


### 4. Update with bundler

Run the following commands to refresh the gem:

```
bundle clean --force
bundle install
```

### 5. Celebrate

That's it.
