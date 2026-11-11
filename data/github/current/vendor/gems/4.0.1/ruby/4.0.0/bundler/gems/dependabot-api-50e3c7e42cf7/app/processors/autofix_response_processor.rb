# frozen_string_literal: true

class AutofixResponseProcessor < ApplicationProcessor
  group_name "autofix_response"
  handle_topic(/code_scanning\.v0\.DependabotAutofixResult\Z/, AutofixResponseHandler)
end
