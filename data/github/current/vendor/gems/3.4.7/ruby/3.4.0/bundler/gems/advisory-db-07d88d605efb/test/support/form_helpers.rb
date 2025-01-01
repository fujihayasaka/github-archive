# frozen_string_literal: true

module FormHelpers
  # Use in integration tests to assert the values set for a given form.
  #
  #   assert_select "form[data-test-selector='my-form']" do |(form)|
  #     data = form_data_for(form)
  #
  #     assert_equal { "user" => { "name" => "laserlemon" } }, data
  #   end
  #
  def form_data_for(form)
    # Remove template elements, which don't contribute to the form data.
    form = form.dup
    form.css("template").each(&:remove)

    raw_form_data = Mechanize::Form.new(form).request_data
    form_data = Rack::Utils.parse_nested_query(raw_form_data)

    # Remove Rails' hidden form fields.
    form_data.delete("_method")
    form_data.delete("utf8")

    form_data
  end

  def assert_form_field(*args, value:, error: false)
    assert_select(*args, count: 1) do
      assert_select "input,textarea,.SelectMenu" do |(field)|
        case field.name
        when "input"
          if value.nil?
            assert_nil field["value"]
          else
            assert_equal value, field["value"]
          end
        when "textarea"
          assert_equal value, field.text.strip
        else
          assert_select ".SelectMenu-item[aria-checked='true']", text: value
        end

        form_group = field.ancestors(".form-group")

        if error
          refute_nil form_group
          assert_select form_group, ".errored"
          assert_select form_group, ".note.error:not([hidden])"
        elsif form_group
          assert_select form_group, ".errored", false
          assert_select form_group, ".warn", false
          assert_select form_group, ".note.error:not([hidden])", false
          assert_select form_group, ".note.warning:not([hidden])", false
        end
      end
    end
  end

  def assert_form_fields(*args, values:, error: false)
    assert_select(*args, count: values.length) do
      assert_select "input,textarea,.SelectMenu" do |(field)|
        value = values.shift
        case field.name
        when "input"
          assert_equal value, field["value"]
        when "textarea"
          assert_equal value, field.text.strip
        else
          assert_select ".SelectMenu-item[aria-checked='true']", text: value
        end

        form_group = field.ancestors(".form-group")

        if error
          refute_nil form_group
          assert_select form_group, ".errored"
          assert_select form_group, ".note.error:not([hidden])"
        elsif form_group
          assert_select form_group, ".errored", false
          assert_select form_group, ".warn", false
          assert_select form_group, ".note.error:not([hidden])", false
          assert_select form_group, ".note.warning:not([hidden])", false
        end
      end
    end
  end
end

module ActiveSupport
  class TestCase
    include FormHelpers
  end
end
