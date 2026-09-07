--[[
  rightalign.lua

  Markdown has no concept of a tab stop, so this filter supplies one.

  Any standalone "@@" in a paragraph becomes a Word tab. Every body paragraph
  style in reference.docx carries a right tab stop at the right margin, so the
  text after the marker snaps flush right:

      **Job Title** --- Company, City @@ May 2026 -- Present

  Whitespace on either side of the marker is swallowed, so the right-aligned
  text starts exactly at the margin.

  Only applies to docx output; other formats fall back to a plain space, so
  `pandoc resume.md -o resume.txt` still reads sensibly.
--]]

local MARKER = "@@"

local function tab_inline()
  if FORMAT:match("docx") then
    return pandoc.RawInline("openxml", "<w:r><w:tab/></w:r>")
  end
  return pandoc.Space()
end

function Inlines(inlines)
  local out = pandoc.List()
  local i = 1
  while i <= #inlines do
    local el = inlines[i]
    if el.t == "Str" and el.text == MARKER then
      -- drop a Space we already emitted before the marker
      while #out > 0 and out[#out].t == "Space" do
        out:remove(#out)
      end
      out:insert(tab_inline())
      -- and skip Spaces that follow it
      i = i + 1
      while i <= #inlines and inlines[i].t == "Space" do
        i = i + 1
      end
    else
      out:insert(el)
      i = i + 1
    end
  end
  return out
end
