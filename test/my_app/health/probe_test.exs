defmodule MyApp.Health.ProbeTest do
  use MyApp.DataCase, async: true

  alias MyApp.Health.Probe

  test "check/0 is true when the database answers" do
    assert Probe.check()
  end

  test "the probe process is running" do
    assert is_pid(Process.whereis(Probe))
  end
end
