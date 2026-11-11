package deploy

import "fmt"

func (r *ActionReference) NameWithVersion() string {
	if len(r.GetPath()) > 0 {
		return fmt.Sprintf("%s/%s@%s", r.GetName(), r.GetPath(), r.GetVersion())
	}
	return fmt.Sprintf("%s@%s", r.GetName(), r.GetVersion())
}
