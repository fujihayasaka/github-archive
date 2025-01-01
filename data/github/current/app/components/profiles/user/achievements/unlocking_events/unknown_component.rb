# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class UnknownComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          def render_accessible_model
            if unlocking_model.respond_to?(:permalink)
              content_tag(:a, "a(n) #{class_name}", class: "Link", href: unlocking_model.permalink)
            else
              content_tag(:span, "a(n) #{class_name}")
            end
          end

          def class_name
            @_class_name ||= begin
              if unlocking_model
                unlocking_model.class.name.underscore.humanize.downcase
              else
                "event"
              end
            end
          end
        end
      end
    end
  end
end
