# typed: true
# frozen_string_literal: true

require "test_helper"

class NodeTest < GitHub::TestCase

  context "#collect_link_urls" do
    test "Returns a single URL target for text with a HREF" do
      data = "This <b>thing</b>, <i>it</i> has <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      assert_equal ["/things"], node.collect_link_urls
    end

    test "Returns an empty array for text with no HREFs" do
      data = "This <b>thing</b>, <i>it</i> has things."
      node = Spam::Node.new(data)
      assert_empty node.collect_link_urls
    end

    test "Returns all URLs for text with multiple HREFs" do
      data = "This <A href='/thing/1'><b>thing</b></a>, <i>it</i> has <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      assert_equal ["/thing/1", "/things"], node.collect_link_urls
    end
  end

  context "#get_fake_tags" do
    test "Returns a Hash" do
      data = "This <b>thing</b>, <i>it</i> has <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      assert node.get_fake_tags.is_a? Hash
    end

    test "Returns empty Hash with no fake tags" do
      data = "This <b>thing</b>, <i>it</i> has <title>woo</title> <table>foo</table> and <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      assert_empty node.get_fake_tags
    end

    test "Returns Hash including all fake tags" do
      data = "This <foo>thing</foo>, <bar>it</bar> has <title><fakeme>odd <takeme>names</takeme> here</fakeme> </title> <table>foo</table> and <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      %w[bar fakeme foo takeme].each do |tag|
        assert node.get_fake_tags.keys.include? tag
      end
    end
  end

  context "#just_text" do
    test "returns proper content for untagged text" do
      data = "This is a thing.  It has things."
      node = Spam::Node.new(data)
      assert_equal data, node.just_text
    end

    test "returns proper content for content with non-nested HTML tags" do
      data = "This <b>thing</b>, <i>it</i> has things."
      node = Spam::Node.new(data)
      assert_equal "This thing, it has things.", node.just_text
    end

    test "returns proper content for content with nested HTML tags" do
      data = "This <b>thing, <i>it</i> has</b> things."
      node = Spam::Node.new(data)
      assert_equal "This thing, it has things.", node.just_text
    end

    test "includes href target text in output" do
      data = "This <b>thing</b>, <i>it</i> has <a href='/things'>things</a>."
      node = Spam::Node.new(data)
      assert_equal "This thing, it has things.", node.just_text
    end
  end

  context "#nothing_but_image_links?" do
    test "clean_copy can handle space within the a href" do
      naughty_data = " \n<b></b>\n \n<c></c>\n \n<d></d>\n \n<e></e>\n \n<f></f>\n<a   href='http://hoz.blogspot.com'> <img  src='http://bp.blogspot.com/gits.jpg'  ></a>"
      node = Spam::Node.new(naughty_data).clean_copy
      assert node.nothing_but_image_links?
    end

    # rubocop:disable Layout/TrailingWhitespace
    test "clean_copy ignores whitespace" do
      naughty_data = " \n<b></b>\n \n<c></c>\n \n<d></d>\n \n<e></e>\n \n<f></f>\n<a   href='http://hoz.blogspot.com'> <img src='http://bp.blogspot.com/gits.jpg'> 
           </a>"
      node = Spam::Node.new(naughty_data).clean_copy
      assert node.nothing_but_image_links?
    end
  end

end
