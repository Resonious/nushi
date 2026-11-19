package regularfile

import "io/fs"

// Owner is never known: a Windows stat has no link count or owner, which
// only a query of an open handle gives (issue #56), so what needs
// them (a preview's save) takes the file as read-only.
func Owner(fs.FileInfo) (links uint64, uid uint32, ok bool) { return 0, 0, false }
