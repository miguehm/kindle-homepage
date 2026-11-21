> **Archived development record.** This is the original inbound feedback
> backlog, kept for historical context only. Items marked done were resolved in
> the releases named below. It is not user documentation; see
> [README.md](../../README.md) for current behavior.

- [x] If an article download fails, create a temporary document with the URL so
      it can be copied and opened manually (the API returns these details).
- [x] Remove the digest.
- [x] KOReader crashes when weather is selected.
- [x] KOReader crashes when the custom posts directory is selected.
- [x] Format the HN URL and source URL as links, not plain text.

Resolved and verified on Kindle PW5 in release 2.0.0 (Phase 14 of `PLAN.md`):
persistent link cards with `hn_url`/`url`/`content_error`, digest removed, no
`nil` gaps in the menu button rows, weather coordinates persisted, and
`<a href>` links in the document metadata (dashboard unchanged).

- [x] Fix interface bleed-through in the title area.
- [x] Allow a custom folder for downloaded documents.

Resolved in release 2.1.0 (Phase 15 of `PLAN.md`): the Shell now paints an
opaque full-screen background so icons from the previous screen no longer bleed
through the title band, and the `TitleBar` uses the Shell as its repaint target.
A new **Custom content folder** option accepts absolute/nested paths (e.g.
`/mnt/us/My Docs/KindleHome`), rejects relative paths, `..` segments and the
KOReader install directory; when empty, `storage_mode`/`documents_subdir` are
used. Already downloaded files are not migrated: they remain in the old folder
and are downloaded again when opened. Verified on Kindle PW5 and confirmed by
the user. The native folder picker and a Reset entry were added in the same
release.

- Open Kindle Home directly from Tools, with settings inside the Kindle Home
  dashboard.
- Show feedback that the dashboard is updating.
- The next-page icon is not displayed correctly.
- There is no previous-page icon on the Hacker News widget.

Implemented in release 2.4.0 (Phase 19 of `PLAN.md`), pending device check:
Tools opens the dashboard without a submenu; the plugin settings live in a
`TouchMenu` opened from the dashboard gear; the hero shows "Updating…" before
the blocking refresh; inverse icons keep their alpha channel; and the HN pager
has a previous arrow with symmetric wrapping (hidden on a single page).

Corrected in release 2.4.1: in 2.4.0 the gear opened a tiny frame because
`TouchMenu` interprets each `tab_item_table` entry as the item array itself, not
as a descriptor with a nested `item_table`. The gear now passes the sections
array directly as a single tab.

- Improve the appearance of the title bar and the settings/exit icons: move
  them further right and align them better.
- Stop the Hacker News pager icons from shifting position when the last page
  has fewer items.

Implemented in release 2.7.0 (Phase 22 of `PLAN.md`), pending visual check on
device: the header uses symmetric margins matching the body, centers the icons
vertically, and uses normalized assets (`header/settings.svg`,
`header/close.svg`). Top Stories absorbs the remaining viewport height and
pins the pager to the bottom, so the arrows stay put on short last pages.

- [x] Remember the page number in the HN widget when re-entering Kindle Home;
      return to page 1 when content is refreshed with the button.
- [x] Allow configuring the number of items per page in the HN widget.

Implemented in release 2.8.0 (Phase 23 of `PLAN.md`), verified on Kindle PW5:
Top Stories remembers the page for the session and only an explicit refresh
(button or Dispatcher) returns to page 1; new **Items per page** setting in
Hacker News (1–10, default 4). Restarting KOReader starts again at page 1
(accepted scope: session-only memory).

- [x] Both HTML and Markdown are downloaded; only Markdown should be kept.

Implemented in release 2.9.0 (Phase 24 of `PLAN.md`), verified on Kindle PW5:
the content folder keeps only Markdown (and link cards); HTML for `ReaderUI` is
rendered to `<DataDir>/cache/kindlehome/articles/` and removed when the reader
or fallback pager closes; legacy adjacent `.md.html` files are migrated on
startup. The canonical copy is never deleted because of `404`/network errors.

- [x] Can Markdown images be displayed via links?

Implemented in release 2.10.0 (Phase 25 of `PLAN.md`), verified on Kindle PW5:
Markdown images render as linked alt text (`![alt](url)` → `<a href="url">alt</a>`)
in the native reader and the fallback pager. Images are not embedded or fetched
implicitly, and unsafe URLs remain plain text.
