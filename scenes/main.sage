{
  "name": "SAGE Craft",
  "sage_scene_version": 5,
  "lighting": {
    "ambientStrength": 0.0,
    "ambientColor": {
      "x": 0,
      "y": 0,
      "z": 0
    },
    "sun": {
      "direction": {
        "x": -0.3,
        "y": -0.9,
        "z": -0.2
      },
      "color": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "intensity": 0.0
    },
    "fog": {
      "enabled": false,
      "color": {
        "x": 0.7,
        "y": 0.82,
        "z": 1.0
      },
      "start": 60.0,
      "end": 110.0
    },
    "skybox": {
      "enabled": false,
      "cubemapDir": "",
      "intensity": 1.0,
      "rotation": 0.0,
      "top": {
        "x": 0.47,
        "y": 0.65,
        "z": 1.0
      },
      "horizon": {
        "x": 0.7,
        "y": 0.82,
        "z": 1.0
      }
    },
    "pointLights": [],
    "spotLights": [],
    "shadows": {
      "distance": 0.0
    }
  },
  "objects": [
    {
      "id": 1,
      "name": "Game",
      "position": {
        "x": 0,
        "y": 0,
        "z": 0
      },
      "rotation": {
        "x": 0,
        "y": 0,
        "z": 0
      },
      "scale": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "color": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "mesh": {
        "type": "none",
        "path": ""
      },
      "script": "assets/scripts/game.lua"
    },
    {
      "id": 2,
      "name": "Player",
      "position": {
        "x": 0,
        "y": 80,
        "z": 0
      },
      "rotation": {
        "x": 0,
        "y": 0,
        "z": 0
      },
      "scale": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "color": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "mesh": {
        "type": "none",
        "path": ""
      }
    },
    {
      "id": 3,
      "name": "Player Camera",
      "position": {
        "x": 0,
        "y": 1.62,
        "z": 0
      },
      "rotation": {
        "x": 0,
        "y": 0,
        "z": 0
      },
      "scale": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "color": {
        "x": 1,
        "y": 1,
        "z": 1
      },
      "mesh": {
        "type": "none",
        "path": ""
      },
      "parent": 2,
      "camera": {
        "projection": "perspective",
        "fov": 70.0,
        "near": 0.05,
        "far": 260.0,
        "orthoHeight": 10.0,
        "primary": true
      },
      "postProcess": {
        "enabled": true,
        "priority": 0,
        "effects": [
          {
            "kind": "tonemap",
            "enabled": true,
            "params": {
              "mode": 0,
              "output": 0
            }
          }
        ]
      }
    }
  ]
}