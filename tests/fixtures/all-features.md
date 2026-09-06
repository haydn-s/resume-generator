<!--
  Exercises every feature the pipeline supports, so the style and marker
  assertions in tests/run.sh have a complete document to check against.
  Placeholder content only -- never real resume data.
-->

::: {custom-style="Name"}
Ada Lovelace
:::

::: {custom-style="Tagline"}
Analytical Engine Programmer
:::

<!-- The backslash before (555) is load-bearing. Pandoc reads a leading
     "(555)" as ordered-list syntax, which swallows the line into a list and
     silently drops the Contact style. Do not remove it. -->
::: {custom-style="Contact"}
\(555) 555-5555 | ada@example.com | example.com/ada
:::

# SECTION HEADING

A plain paragraph directly under a heading, which takes FirstParagraph.

**Entry line**, City, ST @@ January 2020 -- Present\
A continuation line held inside the same paragraph by a hard break.

A second paragraph, which takes the between-entry BodyText gap.

## Company Heading | City, ST @@ January 2018 -- December 2019

*Role Title* @@ June 2019 -- December 2019

- A bullet carrying no date, as the document-wide invariant requires.
- A second bullet, to exercise the between-bullet gap.

*Earlier Role* @@ January 2018 -- June 2019

- A bullet under the second role.
