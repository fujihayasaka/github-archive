# typed: true
# frozen_string_literal: true

class Platform::Models::FileType < SimpleDelegator
  attr_reader :tree_entry

  def initialize(tree_entry)
    super(tree_entry)
    @tree_entry = tree_entry
  end

  def platform_type_name
    return "MarkdownFileType" if @tree_entry.markdown?
    return "ImageFileType"    if @tree_entry.image?
    return "PdfFileType"      if @tree_entry.pdf?
    "TextFileType"
  end
end
