import json
C = {
 "grey": (163,162,165), "dark": (99,95,98), "red": (196,40,28), "blue": (13,105,172),
 "yellow": (245,205,48), "green": (75,151,75), "white": (242,243,243),
}
def col(n): r,g,b = C[n]; return {"Color3": [r/255, g/255, b/255]}
def part(size, pos, color, label=None, cls="Part", extra=None):
    props = {
        "Size": {"Vector3": list(size)}, "CFrame": {"CFrame": {"position": list(pos), "orientation": [[1,0,0],[0,1,0],[0,0,1]]}},
        "Anchored": {"Bool": True}, "Color": col(color),
        "TopSurface": {"Enum": 3}, "BottomSurface": {"Enum": 4},
    }
    if extra: props.update(extra)
    inst = {"$className": cls, "$properties": props}
    if label:
        inst["Label"] = {"$className": "BillboardGui", "$properties": {
            "Size": {"UDim2": [[0, 260], [0, 44]]},
            "StudsOffset": {"Vector3": [0, size[1]/2 + 2.5, 0]},
            "MaxDistance": {"Float32": 120},
        }, "Text": {"$className": "TextLabel", "$properties": {
            "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": {"Float32": 1},
            "Text": {"String": label}, "TextScaled": {"Bool": True},
            "TextColor3": {"Color3": [1, 1, 1]}, "TextStrokeTransparency": {"Float32": 0},
            "Font": {"Enum": 2},
        }}}
    return inst

course = {
  "$className": "Folder",
  "JumpBox": part((16,4,16), (-30,2,40), "blue", "Jump box (4 high) - coyote/buffer test"),
  "MantleLedge": part((16,9,16), (-30,4.5,72), "red", "Ledge (9 high) - too high to jump, for ledge climb later"),
  "VaultBox": part((12,3,2), (0,1.5,40), "yellow", "Vault box (3 high) - auto-vault later"),
  "SlideGapRoof": part((14,2,8), (0,4,80), "yellow", "Slide gap (3 clearance) - auto-slide later"),
  "SlideGapLeft": part((2,3,8), (-6,1.5,80), "yellow"),
  "SlideGapRight": part((2,3,8), (6,1.5,80), "yellow"),
  "TallWall": part((2,24,48), (34,12,56), "grey", "Tall wall - jump into it / wall run later"),
  "FallTowerTruss": part((2,80,2), (-60,40,0), "dark", None, cls="TrussPart"),
  "FallTowerTop": part((16,1,16), (-60,80.5,9), "green", "Fall tower (80 high) - climb the truss, jump off"),
  "Runway": part((12,0.2,200), (60,0.1,40), "white", "Runway - run/turn testing", extra={"CanCollide": {"Bool": True}}),
}

project = {
 "name": "BattlegroundsGame",
 "tree": {
  "$className": "DataModel",
  "ReplicatedStorage": {"$className": "ReplicatedStorage",
     "Movement": {"$path": "src/shared/Movement"}},
  "StarterPlayer": {"$className": "StarterPlayer",
     "$properties": {"CharacterUseJumpPower": {"Bool": False}, "CharacterJumpHeight": {"Float32": 7.2}, "GameSettingsAvatar": {"Enum": 0}},
     "StarterPlayerScripts": {"$className": "StarterPlayerScripts", "$path": "src/client"},
     "StarterCharacterScripts": {"$className": "StarterCharacterScripts", "$path": "src/character"}},
  "StarterGui": {"$className": "StarterGui"}, "StarterPack": {"$className": "StarterPack"},
  "ServerScriptService": {"$className": "ServerScriptService", "$path": "src/server"}, "Lighting": {"$className": "Lighting"},
  "Workspace": {"$className": "Workspace",
     "Baseplate": part((512,20,512), (0,-10,0), "grey"),
     "SpawnLocation": part((12,1,12), (0,0.5,0), "dark", None, cls="SpawnLocation",
                           extra={"Duration": {"Int32": 0}, "Neutral": {"Bool": True}}),
     "MovementTestCourse": course},
 }
}
json.dump(project, open(__import__("os").path.join(__import__("os").path.dirname(__file__), "..", "default.project.json"),"w"), indent=2)
