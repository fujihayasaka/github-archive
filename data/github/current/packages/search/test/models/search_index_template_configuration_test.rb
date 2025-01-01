# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchIndexTemplateConfigurationTest < GitHub::TestCase
  setup do
    @postfix  = Elastomer::Environment.postfix
    @fullname = "audit_log#@postfix-42"
  end

  teardown do
    tmpl = Elastomer.client.template(@fullname)
    tmpl.delete if tmpl.exists?

    tmpl = Elastomer.client.template("audit_log#{@postfix}_template")
    tmpl.delete if tmpl.exists?
  end

  test "setting the fullname updates the template type and version, too" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    model.save

    assert_equal "audit_log#@postfix", model.template_type
    assert_equal 42, model.template_version
  end

  test "setting the version updates the fullname on save" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    model.save

    model.template_version = 12

    assert_equal @fullname, model.fullname
    model.save
    assert_equal "audit_log#{@postfix}-12", model.fullname
  end

  test "queries the search cluster for template existence" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    refute model.exists?, "search index template does not exist on the search cluster"
  end

  test "generates a version SHA from the current mappings and settings in code" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default", version_sha: "abc123"
    model.save

    assert_equal "abc123", model.version_sha
    refute_equal model.version_sha, model.current_version_sha
  end

  test "creating a model also creates the template on the search cluster" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    refute model.exists?, "the template should not exist"

    model.save
    assert model.exists?, "the template should now exist"
  end

  test "deleting a model also deletes the template from the search cluster" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    model.save
    assert model.exists?, "the template should now exist"

    model.destroy
    refute model.exists?, "the template should not exist"
  end

  test "making the model primary also makes the template primary on the sarch cluster" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default"
    model.save

    refute model.primary?, "should not be primary"
    aliases = model.get_template["aliases"]
    assert_empty aliases, "no aliases should be present"

    model.add_primary

    assert model.primary?, "should be primary"
    aliases = model.get_template["aliases"]
    refute_empty aliases, "aliases should be present"
  end

  test "removing the primary tag from the model also removes the primary alias from the template" do
    model = SearchIndexTemplateConfiguration.new fullname: @fullname, cluster: "default", is_primary: true
    model.save

    assert model.primary?, "should be primary"
    aliases = model.get_template["aliases"]
    refute_empty aliases, "aliases should be present"

    model.remove_primary

    refute model.primary?, "should not be primary"
    aliases = model.get_template["aliases"]
    assert_empty aliases, "no aliases should be present"
  end

  context "old-style audit log template name" do
    test "setting the fullname updates the template type and version, too" do
      model = SearchIndexTemplateConfiguration.new fullname: "audit_log#{@postfix}_template", cluster: "default"
      model.save

      assert_equal "audit_log#@postfix", model.name
      assert_equal 0, model.template_version
    end

    test "setting the version does nothing" do
      model = SearchIndexTemplateConfiguration.new fullname: "audit_log#{@postfix}_template", cluster: "default"
      model.save

      model.template_version = 12

      assert_equal "audit_log#{@postfix}_template", model.fullname
      model.save

      assert model.errors[:fullname].any?, "fullname is out of sync with the version"
    end
  end
end
