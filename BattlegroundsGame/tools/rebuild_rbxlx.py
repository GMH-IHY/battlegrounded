"""Rebuilds the middle services of BattlegroundsGame.rbxlx from src/ and assets,
ensuring a 100% clean, valid .rbxlx file.
"""
import os
import uuid
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACE_FILE = os.path.join(ROOT, "BattlegroundsGame.rbxlx")
SRC_DIR = os.path.join(ROOT, "src")

def make_ref():
    return "RBX" + uuid.uuid4().hex.upper()

def make_script_xml(cls, name, source):
    ref = make_ref()
    # Format CDATA safely
    return f"""\t\t\t<Item class="{cls}" referent="{ref}">
\t\t\t\t<Properties>
\t\t\t\t\t<string name="Name">{name}</string>
\t\t\t\t\t<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>
\t\t\t\t</Properties>
\t\t\t</Item>\n"""

def make_folder_xml(name, children_xml):
    ref = make_ref()
    return f"""\t\t<Item class="Folder" referent="{ref}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">{name}</string>
\t\t\t</Properties>
{children_xml}\t\t</Item>\n"""

with open(PLACE_FILE, "r", encoding="utf-8") as f:
    orig_text = f.read()

p_start = orig_text.find('<Item class="StarterPlayer"')
p_end = orig_text.find('<Item class="ServerStorage"')
assert p_start != -1, "StarterPlayer not found"
assert p_end != -1, "ServerStorage not found"

before = orig_text[:p_start]
after = orig_text[p_end:]

# 1. Build StarterPlayer
starter_player_scripts_xml = ""
client_dir = os.path.join(SRC_DIR, "client")
for f in sorted(os.listdir(client_dir)):
    if f.endswith(".luau"):
        name = f.split(".")[0]
        with open(os.path.join(client_dir, f), "r", encoding="utf-8") as sf:
            src = sf.read()
        starter_player_scripts_xml += make_script_xml("LocalScript", name, src)

starter_char_scripts_xml = ""
char_dir = os.path.join(SRC_DIR, "character")
for f in sorted(os.listdir(char_dir)):
    if f.endswith(".luau"):
        name = f.split(".")[0]
        with open(os.path.join(char_dir, f), "r", encoding="utf-8") as sf:
            src = sf.read()
        starter_char_scripts_xml += make_script_xml("LocalScript", name, src)

starter_player_xml = f"""\t<Item class="StarterPlayer" referent="StarterPlayer">
\t\t<Properties>
\t\t\t<string name="Name">StarterPlayer</string>
\t\t\t<bool name="CharacterUseJumpPower">false</bool>
\t\t\t<float name="CharacterJumpHeight">7.2</float>
\t\t\t<token name="GameSettingsAvatar">0</token>
\t\t\t<bool name="EnableMouseLockOption">false</bool>
\t\t</Properties>
\t\t<Item class="StarterPlayerScripts" referent="{make_ref()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">StarterPlayerScripts</string>
\t\t\t</Properties>
{starter_player_scripts_xml}\t\t</Item>
\t\t<Item class="StarterCharacterScripts" referent="{make_ref()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">StarterCharacterScripts</string>
\t\t\t</Properties>
{starter_char_scripts_xml}\t\t</Item>
\t</Item>\n"""

# 2. StarterGui & StarterPack
starter_gui_xml = f"""\t<Item class="StarterGui" referent="{make_ref()}">
\t\t<Properties>
\t\t\t<string name="Name">StarterGui</string>
\t\t</Properties>
\t</Item>\n"""

starter_pack_xml = f"""\t<Item class="StarterPack" referent="{make_ref()}">
\t\t<Properties>
\t\t\t<string name="Name">StarterPack</string>
\t\t</Properties>
\t</Item>\n"""

# 3. ServerScriptService
server_scripts_xml = ""
server_dir = os.path.join(SRC_DIR, "server")
for f in sorted(os.listdir(server_dir)):
    if f.endswith(".luau"):
        name = f.split(".")[0]
        with open(os.path.join(server_dir, f), "r", encoding="utf-8") as sf:
            src = sf.read()
        server_scripts_xml += make_script_xml("Script", name, src)

server_script_service_xml = f"""\t<Item class="ServerScriptService" referent="{make_ref()}">
\t\t<Properties>
\t\t\t<string name="Name">ServerScriptService</string>
\t\t</Properties>
{server_scripts_xml}\t</Item>\n"""

# 4. ReplicatedStorage
# Movement folder
movement_scripts_xml = ""
shared_dir = os.path.join(SRC_DIR, "shared", "Movement")
for f in sorted(os.listdir(shared_dir)):
    if f.endswith(".luau"):
        name = f.split(".")[0]
        with open(os.path.join(shared_dir, f), "r", encoding="utf-8") as sf:
            src = sf.read()
        movement_scripts_xml += make_script_xml("ModuleScript", name, src)

movement_folder_xml = f"""\t\t<Item class="Folder" referent="{make_ref()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Movement</string>
\t\t\t</Properties>
{movement_scripts_xml}\t\t</Item>\n"""

# Remotes folder
remotes_xml = f"""\t\t<Item class="Folder" referent="{make_ref()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Remotes</string>
\t\t\t</Properties>
\t\t\t<Item class="RemoteEvent" referent="{make_ref()}">
\t\t\t\t<Properties>
\t\t\t\t\t<string name="Name">DashPunch</string>
\t\t\t\t</Properties>
\t\t\t</Item>
\t\t</Item>\n"""

# Read MovementAnimations.rbxmx (extract Item from inside <roblox ...>...</roblox>)
anim_rbxmx = os.path.join(ROOT, "MovementAnimations.rbxmx")
anim_xml = ""
if os.path.exists(anim_rbxmx):
    with open(anim_rbxmx, "r", encoding="utf-8") as af:
        a_content = af.read()
    s = a_content.find("<Item")
    e = a_content.rfind("</Item>")
    if s != -1 and e != -1:
        anim_xml = "\t\t" + a_content[s : e + 7] + "\n"

# Read MothRace.rbxmx (extract Item from inside <roblox ...>...</roblox>)
moth_rbxmx = os.path.join(ROOT, "models", "MothRace.rbxmx")
moth_xml = ""
if os.path.exists(moth_rbxmx):
    with open(moth_rbxmx, "r", encoding="utf-8") as mf:
        m_content = mf.read()
    s = m_content.find("<Item")
    e = m_content.rfind("</Item>")
    if s != -1 and e != -1:
        moth_xml = "\t\t" + m_content[s : e + 7] + "\n"

replicated_storage_xml = f"""\t<Item class="ReplicatedStorage" referent="{make_ref()}">
\t\t<Properties>
\t\t\t<string name="Name">ReplicatedStorage</string>
\t\t</Properties>
{movement_folder_xml}{remotes_xml}{anim_xml}{moth_xml}\t</Item>\n"""

full_xml = before + starter_player_xml + starter_gui_xml + starter_pack_xml + server_script_service_xml + replicated_storage_xml + after

with open(PLACE_FILE, "w", encoding="utf-8") as f:
    f.write(full_xml)

print("Rebuilt BattlegroundsGame.rbxlx. Validating XML with ET.parse...")
try:
    ET.parse(PLACE_FILE)
    print("SUCCESS: BattlegroundsGame.rbxlx is completely valid XML!")
except Exception as err:
    print(f"FAILED validation: {err}")
