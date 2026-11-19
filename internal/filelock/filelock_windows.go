package filelock

import (
	"errors"
	"math"
	"os"

	"golang.org/x/sys/windows"
)

// held is false: Windows tells whether a range is locked only to an
// attempt to lock it, and taking the lock to let it go races an agent
// starting at that moment (held_linux.go), so a session open elsewhere
// isn't seen by its lock here (issue #56).
func held(*os.File) bool { return false }

// tryLock takes the whole of f with LockFileEx, exclusive, without
// waiting, as Rust's File::try_lock does on Windows: errBusy while
// another handle holds it, this process's own included.
func tryLock(f *os.File) error {
	var ol windows.Overlapped
	err := windows.LockFileEx(windows.Handle(f.Fd()), windows.LOCKFILE_EXCLUSIVE_LOCK|windows.LOCKFILE_FAIL_IMMEDIATELY, 0, math.MaxUint32, math.MaxUint32, &ol)
	if errors.Is(err, windows.ERROR_LOCK_VIOLATION) {
		return errBusy
	}
	return err
}

// release unlocks f, then closes it. Closing alone lets the lock go when
// the system gets to it, which Microsoft says depends on its load (and
// says to unlock first), so Ante trying the lock just after could find it
// still held.
func release(f *os.File) {
	var ol windows.Overlapped
	_ = windows.UnlockFileEx(windows.Handle(f.Fd()), 0, math.MaxUint32, math.MaxUint32, &ol) // closing lets it go anyway
	_ = f.Close()
}
