# typed: true
# frozen_string_literal: true

# Without this change various parts of rdoc get lazily autloaded via the html
# pipeline. https://github.com/github/markup/blob/7981c280b089819afd51361b55a8062fa62b20d4/lib/github/markup/rdoc.rb#L14
# Requiring files in the middle of a request is not ideal:
#
# - Slows down the request (we have to parse and compile the new files)
# - Slows down later requests (caches get busted, JIT compiled code gets invalidated)
# - Requires more memory overall (each process has to load these files, rather than sharing)
#
# The JIT invalidations are particularly problematic, since they are happening
# after we've compiled enough code to hit some edge case bug that occasionally
# causes YJIT to crash. See https://github.com/github/ruby-architecture/issues/1129 for details
#
# This loads some of these rdoc files upfront (when we are configured to
# eager load) to avoid these problems.
GitHub::Application.configure do
  config.after_initialize do
    if config.eager_load
      require "rdoc"
      require "rdoc/markup"
      require "rdoc/markup/blank_line"
      require "rdoc/markup/block_quote"
      require "rdoc/markup/document"
      require "rdoc/markup/formatter"
      require "rdoc/markup/hard_break"
      require "rdoc/markup/heading"
      require "rdoc/markup/include"
      require "rdoc/markup/indented_paragraph"
      require "rdoc/markup/list"
      require "rdoc/markup/list_item"
      require "rdoc/markup/paragraph"
      require "rdoc/markup/parser"
      require "rdoc/markup/raw"
      require "rdoc/markup/rule"
      require "rdoc/markup/table"
      require "rdoc/markup/to_html"
      require "rdoc/markup/verbatim"
      require "rdoc/options"
      require "rdoc/rdoc"
    end
  end
end
