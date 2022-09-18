job "minecraft" {
  constraint {
    attribute = "${attr.kernel.name}"
    value = "linux"
  }

  datacenters = ["dc1"]
  meta {
    Customer = "Kids"
    For = "Fun"
  }
  priority = 20
  update {

  }
  // constraint {
  //   java version
  // }
  all_at_once = true
  affinity {
    attribute = "${attr.cpu.numcores}"
    operator = ">="
    value = "3"
    weight = 90
  }
  reschedule {
    attempts = 1
    interval = "15s"
    delay = "10s"
    unlimited = false
  }

  group "server" {
    restart {
      attempts = 1
      delay = "10s"
    }
    network {
      port "server" {
        static = 25565
      }
    }
    service {
      tags = ["minecraft", "server"]
      port = "server"

      check {
        type = "tcp"
        port = "server"
        interval = "10s"
        timeout = "5s"
      }
    }
    task "main" {
      resources {
        cpu = 3000
        memory = 2048
      }
      driver = "java"
      config {
        jar_path = "local/paper.jar"
        jvm_options = ["-Xmx2048M", "-Xms2048M"]
        args = ["--nogui"]
      }
      artifact {
        destination = "local/paper.jar"
        source = "https://api.papermc.io/v2/projects/paper/versions/1.19.2/builds/153/downloads/paper-1.19.2-153.jar"
        mode = "file"
      }
      template {
        destination = "eula.txt"
        data = "eula=true"
        perms = "666"

      }

//       template {
//         destination = "server.properties"
//         data = <<EOF
// allow-nether=true
// difficulty=1
// gamemode=0
// hellworld=false
// level-name=world
// max-connections=3
// max-players=16
// motd=Welcome to my Minecraft Server\!
// online-mode=true
// port=25565
// public=false
// pvp=true
// server-name=Minecraft Server
// spawn-animals=true
// spawn-monsters=true
// verify-names=true
// view-distance=10
// EOF
        // perms = "666"
        // uid = 65534
        // guid = 65534
      //}
    }
  }
}
