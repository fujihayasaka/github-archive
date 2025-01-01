# typed: strict
# frozen_string_literal: true

class SourceImportMailer < ApplicationMailer
  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(ActionMailer::MessageDelivery) }
  def self.import_success(options); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(ActionMailer::MessageDelivery) }
  def self.import_failure(options); end
end
