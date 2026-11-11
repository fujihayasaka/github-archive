# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class BaseComponent < ApplicationComponent
          sig { params(submitted_application: EducationDeveloperPackApplicationMetadata).void }
          def initialize(submitted_application:)
            @submitted_application = submitted_application
          end

          sig { returns(String) }
          def call
            render(
              Primer::Box.new(
                align_items: :center,
                classes: "user-select-none",
                display: :flex,
                pr: 3,
                py: 2,
              ),
            ) do
              safe_join([
                render(
                  Primer::Box.new(
                    col: 1,
                    color: :muted,
                    font_size: :small,
                    text_align: :center,
                  ),
                ) do
                  render(Primer::Beta::Octicon.new(icon: "chevron-right"))
                end,
                render(
                  Primer::Box.new(
                    display: :flex,
                    flex: :auto,
                    justify_content: :space_between,
                    align_items: :center,
                  ),
                ) do
                  safe_join([
                    render(
                      Primer::Beta::Text.new(
                        my: 1,
                        col: 3,
                        px: 3,
                        display: :inline_block,
                        font_weight: :bold,
                        font_size: 6,
                      ).with_content(submitted_application.status_label),
                    ),
                    render(
                      Primer::Box.new(my: 1, col: 5, px: 3, width: :full).
                        with_content(progress_bar_component),
                    ),
                    render(
                      Primer::Beta::Text.new(col: 3, font_size: 6, text_align: :right).
                        with_content(time_words),
                    ),
                  ])
                end,
              ])
            end
          end

          private

          sig { returns(T.untyped) }
          def progress_bar_component
            raise NotImplementedError, "Subclasses must implement #progress_bar_component"
          end

          sig { returns(T.untyped) }
          def time_words
            raise NotImplementedError, "Subclasses must implement #time_words"
          end

          sig { returns(EducationDeveloperPackApplicationMetadata) }
          attr_reader :submitted_application

          sig { returns(User) }
          def user
            T.must(submitted_application.user)
          end

          sig { returns(T::Boolean) }
          def render?
            feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
          end
        end
      end
    end
  end
end
