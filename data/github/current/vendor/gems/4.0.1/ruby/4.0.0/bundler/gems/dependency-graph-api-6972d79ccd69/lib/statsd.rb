# This file and constant aliasing exist to appease ruby-kafka, which presumes
# the use of earlier versions of dogstatsd-ruby which defined Statsd without
# namespacing.
Statsd = Datadog::Statsd
