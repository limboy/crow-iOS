# Crow for iOS

A read-only iOS 26+ viewer for [Crow](../crow) documents, served by [crow-service](../crow-service).

- **Documents** — every `.crow` document on the server, with its tables and record counts
- **Saved views** — each table opens on its saved views:
  - **Table** — a spreadsheet grid with a pinned header, scrolling both ways
  - **Kanban** — one column per choice of a select field
  - **Gallery** — cards with cover images
  - **Calendar** — an agenda grouped by day
  - **Dashboard** — record counts broken down by each select/checkbox field
- **Search, sort and filter** — search across values, sort by any field, filter by a choice
- **Customize** — from the Sort & Filter menu, choose which fields a view shows; for gallery and
  kanban cards also the image field, its shape (16:9 to 3:5, or the image's original shape) and,
  in a gallery, 1–3 columns or auto. Everything starts from the saved view's config, is remembered
  per view on the device, and *Reset to Saved View* undoes it
- **Record detail** — every field, with images (pinch to zoom), video and audio playback,
  attachments, and links that open related records in other tables

## Running

Start crow-service on your Mac:

```bash
cd ../crow-service && bun run src/index.ts --dir ~/Documents/Crow
```

Then build the app. The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open CrowViewer.xcodeproj
```

The app connects to `http://localhost:8090` by default, which works in the simulator. On a
device, tap the server button and enter your Mac's local address (e.g. `http://192.168.1.10:8090`).

## Notes

Views follow their saved `config` from crow-service (group field, cover field and aspect ratio,
hidden fields, sorts, row height). Against an older crow-service that doesn't send `config`, the
app falls back to guesses: a board groups by the first select field, a gallery uses the first image
field as its cover, and every field is shown. Saved view filters and dashboard chart definitions
are not applied; the dashboard charts each choice field instead.
