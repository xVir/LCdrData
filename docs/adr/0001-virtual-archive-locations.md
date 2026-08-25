# Virtual archive locations

A panel inside an archive is at a **location**, not a filesystem **directory**. Listing reads the zip index and synthesizes folder rows; members are extracted only when copied out, previewed, or dragged. Fake `file://` paths (`…/archive.zip/folder`) and extracting the whole archive to a temp directory were rejected: the first makes every FileManager call a footgun, the second is slow and easy to desync.

Status: accepted
