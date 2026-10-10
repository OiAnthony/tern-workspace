-- Tern 0.6.2 names userdata in ExportCall.wait without declaring the type.
-- Luau exposes the real opaque type through newproxy; do not alter tern.d.luau.
export type userdata = typeof(newproxy())
