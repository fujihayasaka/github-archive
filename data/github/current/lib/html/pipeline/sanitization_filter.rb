require "sanitize"

module HTML
  class Pipeline
    # HTML filter with sanization routines and whitelists. This module defines
    # what HTML is allowed in user provided content and fixes up issues with
    # unbalanced tags and whatnot.
    #
    # See the Sanitize docs for more information on the underlying library:
    #
    # https://github.com/rgrove/sanitize/#readme
    #
    # Context options:
    #   :whitelist      - The sanitizer whitelist configuration to use. This
    #                     can be one of the options constants defined in this
    #                     class or a custom sanitize options hash.
    #   :anchor_schemes - The URL schemes to allow in <a href> attributes. The
    #                     default set is provided in the ANCHOR_SCHEMES
    #                     constant in this class. If passed, this overrides any
    #                     schemes specified in the whitelist configuration.
    #
    # This filter does not write additional information to the context.
    class SanitizationFilter < Filter
      LISTS     = Set.new(%w(ul ol).freeze)
      LIST_ITEM = 'li'.freeze

      # List of table child elements. These must be contained by a <table> element
      # or they are not allowed through. Otherwise they can be used to break out
      # of places we're using tables to contain formatted user content (like pull
      # request review comments).
      TABLE_ITEMS = Set.new(%w(tr td th).freeze)
      TABLE = 'table'.freeze
      TABLE_SECTIONS = Set.new(%w(thead tbody tfoot).freeze)

      # These schemes are the only ones allowed in <a href> attributes by default.
      ANCHOR_SCHEMES = [+'http', +'https', +'mailto', +'xmpp', :relative, +'github-windows', +'github-mac'].freeze

      # The main sanitization whitelist. Only these elements and attributes are
      # allowed through by default.
      WHITELIST = {
        :elements => %w(
          h1 h2 h3 h4 h5 h6 h7 h8 br b i strong em a pre code img tt
          div span ins del sup sub p ol ul table thead tbody tfoot blockquote mark
          dl dt dd kbd q samp var hr ruby rt rp li tr td th s strike summary details picture source
          tracking-block tracking-block-omnibar copilot-directive
        ),
        :remove_contents => ['script'],
        :attributes => {
          'a'          => ['href', 'aria-label', 'aria-describedby', 'aria-labelledby'],
          'blockquote' => ['cite'],
          'del'        => ['cite'],
          'div'        => ['itemscope', 'itemtype'],
          'dl'         => ['aria-label', 'aria-describedby', 'aria-labelledby'],
          'img'        => ['src', 'longdesc', 'aria-label', 'aria-describedby', 'aria-labelledby'],
          'ins'        => ['cite'],
          'ol'         => ['aria-label', 'aria-describedby', 'aria-labelledby'],
          'pre'        => ['data-meta'],
          'q'          => ['cite'],
          'source'     => ['media', 'srcset'],
          'summary'    => ['aria-label', 'aria-describedby', 'aria-labelledby'],
          'table'      => ['aria-label', 'aria-describedby', 'aria-labelledby'],
          'ul'         => ['aria-label', 'aria-describedby', 'aria-labelledby'],
          'video'      => ['controls', 'muted', 'src', 'aria-label', 'aria-describedby', 'aria-labelledby'],
          :all         => ['abbr', 'accept', 'accept-charset',
                           'accesskey', 'action', 'align', 'alt', 'axis',
                           'border', 'cellpadding', 'cellspacing', 'char',
                           'charoff', 'charset', 'checked',
                           'clear', 'cols', 'colspan', 'color',
                           'compact', 'coords', 'datetime', 'dir',
                           'disabled', 'enctype', 'for', 'frame',
                           'headers', 'height', 'hreflang',
                           'hspace', 'ismap', 'label', 'lang',
                           'maxlength', 'media', 'method',
                           'multiple', 'name', 'nohref', 'noshade',
                           'nowrap', 'open', 'prompt', 'readonly', 'rel', 'rev',
                           'rows', 'rowspan', 'rules', 'scope',
                           'selected', 'shape', 'size', 'span',
                           'start', 'summary', 'tabindex', 'target',
                           'title', 'type', 'usemap', 'valign', 'value',
                           'vspace', 'width', 'itemprop']
        },
        :protocols => {
          'a'          => {'href' => ANCHOR_SCHEMES},
          'blockquote' => {'cite' => [+'http', +'https', :relative]},
          'del'        => {'cite' => [+'http', +'https', :relative]},
          'ins'        => {'cite' => [+'http', +'https', :relative]},
          'q'          => {'cite' => [+'http', +'https', :relative]},
          'source'     => {'srcset' => [+'http', +'https', :relative]},
          'img'        => {
            'src'      => [+'http', +'https', :relative],
            'longdesc' => [+'http', +'https', :relative]
          },
          'video'      => { 'src' => GitHub.ssl? ? [+'https', :relative] : [+'http', +'https', :relative] }
        },
        :transformers => [
          # Top-level <li> elements are removed because they can break out of
          # containing markup.
          lambda { |env|
            name, node = env[:node_name], env[:node]
            if name == LIST_ITEM && !node.ancestors.any?{ |n| LISTS.include?(n.name) }
              node.replace(node.children)
            end
          },

          # Table child elements that are not contained by a <table> are removed.
          lambda { |env|
            name, node = env[:node_name], env[:node]
            if (TABLE_SECTIONS.include?(name) || TABLE_ITEMS.include?(name)) && !node.ancestors.any? { |n| n.name == TABLE }
              node.replace(node.children)
            end
          }
        ]
      }

      # A more limited sanitization whitelist. This includes all attributes,
      # protocols, and transformers from WHITELIST but with a more locked down
      # set of allowed elements.
      LIMITED = WHITELIST.merge(
        :elements => %w(b i strong em a pre code img ins del sup sub p ol ul li))

      # Strip all HTML tags from the document.
      FULL = { :elements => [] }

      # Sanitize markup using the Sanitize library.
      def call
        Sanitize.clean_node!(doc, whitelist)
      end

      # The whitelist to use when sanitizing. This can be passed in the context
      # hash to the filter but defaults to WHITELIST constant value above.
      def whitelist
        whitelist = context[:whitelist] || WHITELIST
        anchor_schemes = context[:anchor_schemes]
        return whitelist unless anchor_schemes
        whitelist = whitelist.dup
        whitelist[:protocols] = (whitelist[:protocols] || {}).dup
        whitelist[:protocols]['a'] = (whitelist[:protocols]['a'] || {}).merge('href' => anchor_schemes)
        whitelist
      end
    end
  end
end
