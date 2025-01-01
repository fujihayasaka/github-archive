# typed: true
# frozen_string_literal: true

module Copilot::Hadron::User::Dependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
  end

  sig { returns(T::Boolean) }
  def hadron_editor_preview_enabled?
    self.feature_preview_enabled?(:copilot_hadron_editor)
  end
end
