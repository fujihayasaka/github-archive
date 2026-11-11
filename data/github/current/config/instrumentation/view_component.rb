# typed: true
# frozen_string_literal: true

GitHub.subscribe "compile.view_component" do |_, start, finish, _, _|
  runtime_ms = (finish - start) * 1000
  GitHub.dogstats.distribution("view_component.compile.time", runtime_ms)
end
