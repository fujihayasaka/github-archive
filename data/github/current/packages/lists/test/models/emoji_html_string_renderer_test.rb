# typed: true
# frozen_string_literal: true

require "test_helper"

class EmojiHtmlStringRendererTest < GitHub::TestCase
  context "#to_html" do
    test "returns nil when name is nil" do
      renderer = EmojiHtmlStringRenderer.new(nil)

      assert_nil renderer.to_html
    end

    test "escapes HTML other than g-emoji tag when render_emoji is true" do
      emoji_str = "hey :grinning: <script>alert();</script> <b><u>what</u></b> <div>hey</div><br/>"
      g_emoji = %Q(#{GRIN_EMOJI})
      renderer = EmojiHtmlStringRenderer.new(emoji_str)

      assert_equal "hey #{g_emoji} &lt;script&gt;alert();&lt;/script&gt; &lt;b&gt;&lt;u&gt;what&lt;/u&gt;&lt;/b&gt; &lt;div&gt;hey&lt;/div&gt;&lt;br/&gt;", renderer.to_html
    end

    test "returns string with emoji HTML for colon emoji when render_emoji is true" do
      expected = %Q(fish 🐟)
      renderer = EmojiHtmlStringRenderer.new("fish :fish:")

      assert_equal expected, renderer.to_html
    end

    test "returns string with emoji HTML for raw emoji" do
      expected = %Q(good times #{GRIN_EMOJI})
      renderer = EmojiHtmlStringRenderer.new("good times #{GRIN_EMOJI}")

      assert_equal expected, renderer.to_html
    end

    test "caches the rendered name when skip_cache is false" do
      emoji_str = "Hey #{GRIN_EMOJI}"
      expected = %Q(Hey #{GRIN_EMOJI})
      cache_key_prefix = "label"
      cache_key = EmojiHtmlStringRenderer.cache_key_for(emoji_str, cache_key_prefix: cache_key_prefix)

      with_cache_enabled do
        assert_nil GitHub.cache.get(cache_key)

        result = EmojiHtmlStringRenderer.new(emoji_str, skip_cache: false, cache_key_prefix: cache_key_prefix).to_html

        assert_equal expected, GitHub.cache.get(cache_key)
        assert_equal expected, result
      end
    end

    test "does not cache the rendered name when skip_cache is true" do
      emoji_str = "plain-text 123"
      expected = %Q(plain-text 123)
      cache_key_prefix = "label"
      cache_key = EmojiHtmlStringRenderer.cache_key_for(emoji_str, cache_key_prefix: cache_key_prefix)

      with_cache_enabled do
        assert_nil GitHub.cache.get(cache_key)

        result = EmojiHtmlStringRenderer.new(emoji_str, skip_cache: true, cache_key_prefix: cache_key_prefix).to_html

        assert_nil GitHub.cache.get(cache_key)
        assert_equal expected, result
      end
    end

    test "does not cache the label name doesn't require rendering" do
      emoji_str = "plain-text 123"
      expected = %Q(plain-text 123)
      cache_key_prefix = "label"
      cache_key = EmojiHtmlStringRenderer.cache_key_for(emoji_str, cache_key_prefix: cache_key_prefix)

      with_cache_enabled do
        assert_nil GitHub.cache.get(cache_key)

        result = EmojiHtmlStringRenderer.new(emoji_str, skip_cache: true, cache_key_prefix: cache_key_prefix).to_html

        assert_nil GitHub.cache.get(cache_key)
        assert_equal expected, result
      end
    end
  end
end
