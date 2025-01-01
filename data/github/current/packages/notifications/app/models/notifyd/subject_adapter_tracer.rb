# typed: true
# frozen_string_literal: true

module Notifyd
  # SubjectAdapterTracer adds tracing to the methods listed below.
  # It is prepended to the SubjectAdapter class so that all the
  # child classes have their methods traced
  module SubjectAdapterTracer
    [
      :attributes,
      :authzd_attributes,
      :email_layout,
      :explicit_recipients,
      :feature_switches,
      :mobile_layout,
      :owner_id,
      :owner_type,
      :reason_groups,
      :related_topics,
      :repository_id,
      :saml_enforcement,
      :trigger,
    ].each do |method_name|
      define_method(method_name) do |*args, &block|
        GitHub.tracer.in_span("notifyd.subject_adapter.#{self.class.name}.#{method_name}", kind: :internal) do
          super(*args, &block)
        end
      end
    end
  end
end
