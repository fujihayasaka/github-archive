# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDatabaseEnterpriseTest < GitHub::TestCase
  context "Vulnerability model" do
    test "considers all attributes for suitability within enterprise environments" do
      considered_attributes = Vulnerability::ATTRIBUTES_FOR_ENTERPRISE + Vulnerability::ATTRIBUTES_NOT_FOR_ENTERPRISE

      Vulnerability.attribute_names.each do |attribute|
        assert considered_attributes.include?(attribute), "Vulnerability##{attribute} overlooked for enterprise environments"
      end
    end

    test "considers all associations for suitability within enterprise environments" do
      considered_associations = Vulnerability::ASSOCIATIONS_FOR_ENTERPRISE + Vulnerability::ASSOCIATIONS_NOT_FOR_ENTERPRISE

      Vulnerability.reflections.each do |association, reflection|
        next if reflection.through_reflection
        assert considered_associations.include?(association), "Vulnerability##{association} overlooked for enterprise environments"
      end
    end

    test "only defines valid attributes and associations for enterprise" do
      considered = Vulnerability::ATTRIBUTES_FOR_ENTERPRISE + Vulnerability::ATTRIBUTES_NOT_FOR_ENTERPRISE +
                   Vulnerability::ASSOCIATIONS_FOR_ENTERPRISE + Vulnerability::ASSOCIATIONS_NOT_FOR_ENTERPRISE
      considered.each do |attribute_or_association|
        assert Vulnerability.attribute_method?(attribute_or_association), "Vulnerability#{attribute_or_association} doesn't exist"
      end
    end
  end

  context "Vulnerability associations that are suitable for enterprise environments" do
    test "consider all attributes for suitability within enterprise environments" do
      Vulnerability.associations_for_enterprise.each do |association|
        klass = T.let(Vulnerability.reflections[association].klass, T.any(
          T.class_of(VulnerableVersionRange),
          T.class_of(VulnerabilityReference),
          T.class_of(CWEReference),
        ))

        considered_attributes = T.must(klass.const_get("ATTRIBUTES_FOR_ENTERPRISE"))

        if klass.const_defined?("ATTRIBUTES_NOT_FOR_ENTERPRISE")
          considered_attributes += klass.const_get("ATTRIBUTES_NOT_FOR_ENTERPRISE")
        end

        klass.attribute_names.each do |attribute|
          assert considered_attributes.include?(attribute), "#{klass}##{attribute} overlooked for enterprise environments"
        end
      end
    end

    test "only define valid attributes for enterprise" do
      Vulnerability.associations_for_enterprise.each do |association|
        klass = T.let(Vulnerability.reflections[association].klass, T.any(
          T.class_of(VulnerableVersionRange),
          T.class_of(VulnerabilityReference),
          T.class_of(CWEReference),
        ))

        considered_attributes = T.must(klass.const_get("ATTRIBUTES_FOR_ENTERPRISE"))

        if klass.const_defined?("ATTRIBUTES_NOT_FOR_ENTERPRISE")
          considered_attributes += klass.const_get("ATTRIBUTES_NOT_FOR_ENTERPRISE")
        end

        considered_attributes.each do |attribute|
          assert klass.attribute_method?(attribute), "#{klass}##{attribute} doesn't exist"
        end
      end
    end

    test "define an attributes_for_enterprise class method" do
      Vulnerability.associations_for_enterprise.each do |association|
        klass = Vulnerability.reflections[association].klass
        assert klass.respond_to?(:attributes_for_enterprise), "#{klass} does not define an attributes_for_enterprise class method"
      end
    end

    test "touch Vulnerability on save" do
      Vulnerability.associations_for_enterprise.each do |association|
        reflection = Vulnerability.reflections[association].inverse_of
        assert reflection.options[:touch], "#{Vulnerability.reflections[association].klass} does not set advisory updated_at timestamp on save"
      end
    end
  end
end
