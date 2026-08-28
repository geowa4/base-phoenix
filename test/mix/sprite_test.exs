defmodule Mix.SpriteTest do
  use ExUnit.Case, async: true

  alias Mix.Sprite

  describe "repo_name/1" do
    test "handles scp-like, ssh://, and https URLs" do
      assert Sprite.repo_name("git@github.com:acme/app.git") == "app"
      assert Sprite.repo_name("ssh://git@example.com:2222/acme/app.git/") == "app"
      assert Sprite.repo_name("https://github.com/acme/app\n") == "app"
    end
  end

  describe "ssh_host/1" do
    test "extracts the host of SSH remotes" do
      assert Sprite.ssh_host("git@github.com:acme/app.git") == "github.com"

      assert Sprite.ssh_host("ssh://git@gitlab.example.com:2222/acme/app.git") ==
               "gitlab.example.com"

      assert Sprite.ssh_host("ssh://gitlab.example.com/acme/app.git") == "gitlab.example.com"
    end

    test "is nil for other transports" do
      assert Sprite.ssh_host("https://github.com/acme/app.git") == nil
      assert Sprite.ssh_host("/srv/git/app.git") == nil
    end
  end

  describe "github_repo/1" do
    test "extracts owner/repo from GitHub remotes" do
      assert Sprite.github_repo("git@github.com:acme/app.git") == "acme/app"
      assert Sprite.github_repo("git@github.com:acme/app\n") == "acme/app"
      assert Sprite.github_repo("ssh://git@github.com/acme/app.git") == "acme/app"
      assert Sprite.github_repo("https://github.com/acme/app/") == "acme/app"
    end

    test "is nil for other hosts" do
      assert Sprite.github_repo("git@gitlab.com:acme/app.git") == nil
      assert Sprite.github_repo("https://example.com/github.com/acme/app") == nil
    end
  end

  describe "elixir_version/1" do
    test "reads the pinned version, ignoring the OTP suffix" do
      assert Sprite.elixir_version("erlang 28.3.3\nelixir 1.20.3-otp-28\n") == "1.20.3"
    end

    test "is nil when elixir is not pinned" do
      assert Sprite.elixir_version("erlang 28.3.3\n") == nil
    end
  end
end
