# typed: true
# frozen_string_literal: true

require "prose_diff"

module GitHub::HTML

  class Diff
    module Dom
      def self.expandable?(node)
        css_classes(node).include?("expandable")
      end

      def self.added?(node)
        node.name == "ins" || css_classes(node).include?("added")
      end

      def self.removed?(node)
        node.name == "del" || css_classes(node).include?("removed")
      end

      def self.changed?(node)
        css_classes(node).include?("changed")
      end

      def self.css_classes(node)
        (node["class"] || "").split(" ")
      end

      def self.fast_and_dangerous_add_class(el, clazz)
        el["class"] = if el["class"].blank?
          clazz
        else
          el["class"] + " #{clazz}"
        end
      end

      def self.add_classes(el, *classes)
        classes = css_classes(el) + classes
        set_classes(el, classes)
      end

      def self.remove_classes(el, *classes)
        classes = css_classes(el) - classes
        set_classes(el, classes)
      end

      def self.set_classes(el, *css_classes)
        el["class"] = css_classes.uniq.join(" ")
        el
      end

      def self.wrap_in_div(el)
        div = Nokogiri::XML::Node.new("div", el.document)
        div["class"] = el["class"] if el["class"]
        el.remove_attribute("class")
        el.replace div
        div << el
        div
      end
    end

    PROSE_DIFF_OPTIONS = {
      css: { unchanged: { only: ProseDiff::Node::TOPLEVEL + %w{table dl}, with: "unchanged" } },
      before_attributes: { attrs: %w{tag href class} },
      wrap: {
        changed: { only: %w{p blockquote pre h1 h2 h3 h4 h5 h6 hr ol ul input}, with: "div" },
      },
      vicinity: {
        widows_and_orphans: "disallowed",
      },
    }

    ATTRS_WITH_TIPSIES = %w{href src}

    attr_reader :html

    def initialize(before_html, after_html, options = {})
      before_html = GitHub::HTMLSafeString::EMPTY unless before_html.present?
      after_html  = GitHub::HTMLSafeString::EMPTY unless after_html.present?

      @before_doc = self.class.parse_and_process_html(before_html, options)
      @after_doc  = self.class.parse_and_process_html(after_html, options)

      @raw_diff = ProseDiff::Diff.new(@before_doc, @after_doc, PROSE_DIFF_OPTIONS).document
      @diff_doc = self.class.post_process_document(@raw_diff, options)

      raw_html = @diff_doc.css("body").children.to_html

      # We assume that if both inputs to ProseDiff are html_safe that the
      # resulting diff between the two is safe.
      raw_html = raw_html.html_safe if before_html.html_safe? && after_html.html_safe? # rubocop:disable Rails/OutputSafety
      @html = raw_html
    end

    def when_visible_changes
      yield self if has_visible_changes?
    end

    def unless_visible_changes
      yield self unless has_visible_changes?
    end

    def has_visible_changes?
      @diff_doc.css(".added, .removed, .changed, del, ins").length > 0
    end

    def self.parse_and_process_html(was_html, options = {})
      doc = Nokogiri::HTML.parse(was_html)
      doc.css("body > ins, body > del, div > ins, div > del").each do |tag|
        span = Nokogiri::XML::Node.new("div", doc)
        span.children = tag.children
        span["class"] = "github-user-#{tag.name}"
        tag.replace(span)
      end
      doc.css("ins, del").each do |tag|
        span = Nokogiri::XML::Node.new("span", doc)
        span.children = tag.children
        span["class"] = "github-user-#{tag.name}"
        tag.replace(span)
      end
      doc
    end

    def self.post_process_document(document, options = {})
      post_process_attrs(document, options)
      post_process_tags(document, options)
      post_process_js_classes(document, options)
      post_process_anchors(document, options)
      post_process_depth(document, options)
      post_process_vicinity(document, options)
      post_process_icons(document, options)
      document
    end

    def self.post_process_icons(document, options)
      if options[:unfold_icon]
        document.css(".expandable.rich-diff-level-zero").each do |expander|
          expander.prepend_child(options[:unfold_icon])
        end
      end

      if options[:moved_up_icon]
        document.css("li.added.moved-up").each do |moved|
          moved.prepend_child(options[:moved_up_icon])
        end
      end

      if options[:moved_down_icon]
        document.css("li.added.moved-down").each do |moved|
          moved.prepend_child(options[:moved_down_icon])
        end
      end
    end

    def self.post_process_vicinity(document, options)
      document.css(".vicinity.changed, .vicinity.added, .vicinity.removed").each do |vicinity|
        Dom.remove_classes(vicinity, "vicinity")
      end
      document.css(".vicinity.unchanged").each do |vicinity|
        Dom.remove_classes(vicinity, "unchanged")
      end
    end

    def self.post_process_depth(document, options)
      document.at("body").children.each do |top_child|
        apply_level_zero(top_child)
      end
    end

    def self.apply_level_zero(el)
      if el.name == "del" || el.name == "ins"
        el.children.each { |child| apply_level_zero(child) }
      else
        Dom.fast_and_dangerous_add_class(el, "rich-diff-level-zero")
        el.children.each { |child| apply_level_one(child) }
      end
    end

    def self.apply_level_one(el)
      if el.name == "del" || el.name == "ins"
        el.children.each { |child| apply_level_one(child) }
      else
        Dom.fast_and_dangerous_add_class(el, "rich-diff-level-one")
      end
    end

    def self.add_tooltip(el, title)
      el["aria-label"] = if original = el["aria-label"]
        titles = original.split ", "
        titles.push title
        titles.join ", "
      else
        title
      end
      Dom.add_classes el, "tooltipped", "tooltipped-n", "tooltipped-multiline"
    end

    def self.post_process_attrs(document, options = {})
      ATTRS_WITH_TIPSIES.each do |attr|
        document.css(".added_#{attr}").each do |el|
          add_tooltip el, "new #{attr}: #{el[attr]}"
        end
        document.css(".removed_#{attr}").each do |el|
          add_tooltip el, "old #{attr}: #{el['data-before-' + attr]}"
        end
        document.css(".changed_#{attr}").each do |el|
          add_tooltip el, "#{attr}: #{el['data-before-' + attr]} -> #{el[attr]}"
        end
      end
      document
    end

    def self.post_process_tags(document, options = {})
      document.css(".changed_tag").each do |el|
        before_tag = el["data-before-tag"].downcase
        after_tag = el.name

        before_tag = before_tag != "span" && before_tag != "text" && before_tag
        after_tag = after_tag != "span" && after_tag != "text" && after_tag

        if before_tag && after_tag
          add_tooltip el, "tag: #{before_tag} -> #{after_tag}"
        elsif before_tag
          add_tooltip el, "old tag: #{before_tag}"
        elsif after_tag
          add_tooltip el, "new tag: #{after_tag}"
        end
        if after_tag == "code"
          attrs = el.attributes
          span = Nokogiri::XML::Node.new("span", document)
          attrs.each do |attribute, attribute_node|
            span[attribute] = attribute_node
          end
          code = Nokogiri::XML::Node.new("code", document)
          code.children = el.children
          span.children = code
          el.replace(span)
        end
      end
      document
    end

    def self.post_process_anchors(document, options = {})
      anchors = document.xpath(%Q{//a[@href != '']})
      anchors.each do |anchor|
        href = anchor["href"]
        if href =~ /^#/
          label = href[1..-1]
          anchor["href"] = "#{options[:render_url_base]}##{label}"
        end
      end
      document
    end

    def self.post_process_js_classes(document, options = {})
      options = { js_classes: %w{js-expandable} }.merge(options)
      options[:js_classes].each do |js_class|
        css_class = js_class[/^js-(.+)$/, 1]
        document.css(".#{css_class}").each do |node|
          Dom.add_classes(node, js_class)
        end
      end
      document
    end
  end

end
