# Instrumentation

Everywhere you have  access to a global `Instrument` object. Instrumenting events using it will automatically send data to DataDog

You can do the following

## Increment a counter

``` ruby
Instrument.increment("my.counter", custom_payload: "here")
```

## Send a count

``` ruby
Instrument.count("my.counter", 12, custom_payload: "here")
```


## Time a block

``` ruby
Instrument.time("my.event", custom_payload: "here") do
  # do stuff here
end
```

## Send a histogram

``` ruby
Instrument.histogram("my.histogram", 32, custom_payload: "here")
```

# Metrics outside of `Instrument`

There are two places where instrument metrics that don't use the global `Instrument` object.

1) Rails provides some event hooks out of the box (see https://guides.rubyonrails.org/active_support_instrumentation.html). These are sent to DataDog by subscribing to them in `config/initializers/instrumentation.rb`. If you need to instrument a Rails hook, do it there.

2) We have some custom GraphQL timing instrumentation. These notifications come from `lib/graphql_timer.rb` and are subscribed to in `config/initializers/instrumentation.rb`.
