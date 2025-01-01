# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class DeveloperPackApplicationFormComponent < ApplicationComponent
        FormTypeClass = T.type_alias do
          T.any(
            T.class_of(DeveloperPackApplication::InitialForm),
            T.class_of(DeveloperPackApplication::NewSchoolForm),
            T.class_of(DeveloperPackApplication::UploadProofForm),
            T.class_of(DeveloperPackApplication::FarFromCampusProofForm),
          )
        end

        FormTypeInstance = T.type_alias do
          T.any(
            DeveloperPackApplication::InitialForm,
            DeveloperPackApplication::NewSchoolForm,
            DeveloperPackApplication::UploadProofForm,
            DeveloperPackApplication::FarFromCampusProofForm,
          )
        end

        FORM_VARIANTS_MAPPING = T.let({
          initial_form: DeveloperPackApplication::InitialForm,
          new_school_form: DeveloperPackApplication::NewSchoolForm,
          upload_proof_form: DeveloperPackApplication::UploadProofForm,
          far_from_campus_proof_form: DeveloperPackApplication::FarFromCampusProofForm,
        }.freeze, T::Hash[Symbol, FormTypeClass])

        sig do
          params(
            form_errors: T::Hash[Symbol, T.nilable(String)],
            form_values: T::Hash[Symbol, T.nilable(String)],
            user: User,
            suggested_schools: T.untyped,
          ).void
        end
        def initialize(form_errors:, form_values:, user:, suggested_schools: nil)
          @form_errors = form_errors
          @form_values = form_values
          @user = user
          @suggested_schools = suggested_schools
        end

        sig { returns(T.nilable(String)) }
        def call
          primer_form_with(
            scope: :dev_pack_form,
            url: helpers.settings_education_developer_pack_applications_path,
            data: { turbo: true },
            p: 2,
          ) do |form|
            render form_variant_instance(form:)
          end
        end

        private

        sig { returns(User) }
        attr_reader :user

        sig { returns(T::Hash[Symbol, T.nilable(String)]) }
        attr_reader :form_errors

        sig { returns(T::Hash[Symbol, T.nilable(String)]) }
        attr_reader :form_values

        sig { returns(T.untyped) }
        attr_reader :suggested_schools

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end

        sig { returns(Symbol) }
        memoize def form_variant
          if form_values[:form_variant].present? && form_errors.present?
            return T.must(form_values[:form_variant]).to_sym
          end

          if form_values == {}
            :initial_form
          elsif form_values[:new_school] == "true"
            :new_school_form
          elsif form_values[:form_variant] == "initial_form" || form_values[:form_variant] == "new_school_form"
            :upload_proof_form
          elsif form_values[:form_variant] == "upload_proof_form"
            :far_from_campus_proof_form
          else
            :initial_form
          end
        end

        sig { params(form: T.untyped).returns(FormTypeInstance) }
        def form_variant_instance(form:)
          new_form_values = form_values.dup

          if form_variant == :new_school_form
            new_form_values = form_values.except(:new_school)
          end

          T.must(FORM_VARIANTS_MAPPING[form_variant]).new(
            form,
            form_errors:,
            form_values: new_form_values,
            user:,
            suggested_schools:,
          )
        end
      end
    end
  end
end
