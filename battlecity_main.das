// BattleCity game by Vyacheslav Maluhin, 2021
// License: The Unlicense
// DasBox Portable is required to run this game (https://github.com/imp5imp5/dasbox/releases)
// This scripting language is daScript (https://dascript.org/)

require daslib/media
require daslib/decs_boost
// options debugger            // uncomment for debug in VS Code
// require daslib/debug        // uncomment for debug in VS Code

[decs_template]
struct CmpVisual
    pos: float2
    dir: float2
    objTypeIdx: int

[decs_template]
struct CmpCollision
    damage: int
    team: int

[decs_template]
struct CmpMobility
    dir: float2
    speed: float

[decs_template]
struct CmpFiring
    cooldown: float
    team: int

[decs_template]
struct CmpHealth
    hp: int

[decs_template]
struct CmpLifetime
    ttl: float

[decs_template]
struct CmpStaticBG
    empty: bool

[decs_template]
struct CmpStaticFG
    empty: bool

[decs_template]
struct CmpControlUser
    canControl: bool

[decs_template]
struct CmpControlBot
    timeNextFire: float
    timeNextDrive: float

[decs_template]
struct CmpMissionRuleKeepAliveToWin
    empty: bool

[decs_template]
struct CmpMissionRuleDestroyAllToWin
    empty: bool

[decs_template]
struct CmpMissionState
    missionResult: int
    keepAliveTotal: int

struct ObjType
    size: float2
    animFreq: float
    texIdx0, texIdx1: int
    explosionObjIdx: int

let
    MAP = [[string[13]
        "2  M  2M    2";
        " B M   B B B ";
        " B    BB BMB ";
        "   B     M   ";
        "T  B  M  BTBM";
        "TT   B  M T  ";
        " BBBTTTM  TB ";
        "   MTB B B B ";
        "MB M B B   B ";
        " B B BBB BMB ";
        " B B         ";
        " B   BBB B B ";
        " B B1BFB BBB "
    ]]

    CELL_SIZE_PX = 32.0
    SPEED_TANK = CELL_SIZE_PX * 1.0
    SPEED_BULLET = CELL_SIZE_PX * 4.0
    COOLDOWN_FIRE_SEC = 1.0
    AI_MAX_DELAY_FIRE_SEC = 6.0
    AI_MAX_DELAY_DRIVE_SEC = 3.0

    MAP_SIZE = int2(length(MAP[0]), length(MAP))
    FIELD_SIZE = float2(CELL_SIZE_PX * float(MAP_SIZE.x), CELL_SIZE_PX * float(MAP_SIZE.y))
    SCREEN_SIZE = float2(FIELD_SIZE.x + 2.0 * CELL_SIZE_PX, FIELD_SIZE.y + 2.0 * CELL_SIZE_PX)
    FIELD_POS = float2((SCREEN_SIZE.x - FIELD_SIZE.x) * 0.5, (SCREEN_SIZE.y - FIELD_SIZE.y) * 0.5)

    DIR_LEFT = float2(-1, 0)
    DIR_RIGHT = float2(1, 0)
    DIR_UP = float2(0, -1)
    DIR_DOWN = float2(0, 1)

var
    textures: array<ImageHandle>
    objTypes: array<ObjType>
    arrowKeysTime <- {{ VK_UP => 0.0; VK_RIGHT => 0.0; VK_LEFT => 0.0; VK_DOWN => 0.0 }}
    isMissionRestartRequested = false
    randomSeed = int4(2021, 11, 12, 1337)
    deleteEntities : array<EntityId>

////////////////////////////////////////////////////////////////////////////////
// DasBox API Funcs
////////////////////////////////////////////////////////////////////////////////

// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize(is_hard_reload: bool)
    set_window_title("BattleCity")
    set_resolution(int(SCREEN_SIZE.x), int(SCREEN_SIZE.y))

    textures |> emplace(create_managed_image("res/tank00.png"))  //  0
    textures |> emplace(create_managed_image("res/tank01.png"))  //  1
    textures |> emplace(create_managed_image("res/tank10.png"))  //  2
    textures |> emplace(create_managed_image("res/tank11.png"))  //  3
    textures |> emplace(create_managed_image("res/env_b.png" ))  //  4
    textures |> emplace(create_managed_image("res/env_m.png" ))  //  5
    textures |> emplace(create_managed_image("res/env_t.png" ))  //  6
    textures |> emplace(create_managed_image("res/flag.png"  ))  //  7
    textures |> emplace(create_managed_image("res/bullet.png"))  //  8
    textures |> emplace(create_managed_image("res/expl_s.png"))  //  9
    textures |> emplace(create_managed_image("res/expl_s.png"))  // 10
    textures |> emplace(create_managed_image("res/expl_b.png"))  // 11
    textures |> emplace(create_managed_image("res/expl_b.png"))  // 12
    for tex in textures
        tex |> make_image_color_transparent(0x000000)
        tex |> set_image_smooth(false)
    textures[10] |> flip_image_x()
    textures[10] |> flip_image_y()
    textures[12] |> flip_image_x()
    textures[12] |> flip_image_y()

    objTypes |> push([[ ObjType animFreq = 0.050, texIdx0 =  0, texIdx1 =  1, explosionObjIdx =  8 ]]) // 0 Tank1
    objTypes |> push([[ ObjType animFreq = 0.050, texIdx0 =  2, texIdx1 =  3, explosionObjIdx =  8 ]]) // 1 Tank2
    objTypes |> push([[ ObjType animFreq = 0.000, texIdx0 =  4, texIdx1 = -1, explosionObjIdx =  7 ]]) // 2 WallB
    objTypes |> push([[ ObjType animFreq = 0.000, texIdx0 =  5, texIdx1 = -1, explosionObjIdx =  7 ]]) // 3 WallM
    objTypes |> push([[ ObjType animFreq = 0.000, texIdx0 =  6, texIdx1 = -1, explosionObjIdx = -1 ]]) // 4 WallT
    objTypes |> push([[ ObjType animFreq = 0.000, texIdx0 =  7, texIdx1 = -1, explosionObjIdx =  8 ]]) // 5 Flag
    objTypes |> push([[ ObjType animFreq = 0.000, texIdx0 =  8, texIdx1 = -1, explosionObjIdx = -1 ]]) // 6 Bullet
    objTypes |> push([[ ObjType animFreq = 0.100, texIdx0 =  9, texIdx1 = 10, explosionObjIdx = -1 ]]) // 7 ExplosionS
    objTypes |> push([[ ObjType animFreq = 0.100, texIdx0 = 11, texIdx1 = 12, explosionObjIdx = -1 ]]) // 8 ExplosionB
    for t in objTypes
        t.size = float2(float(textures[t.texIdx0].width) / 16.0 * CELL_SIZE_PX, float(textures[t.texIdx0].height) / 16.0 * CELL_SIZE_PX)

    if is_hard_reload
        restart_mission(true)

// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)
    if get_key(VK_ESCAPE)
        schedule_quit_game()

    decs_stage("input")
    commit()

    decs_stage("update")
    for delEid in deleteEntities
        delete_entity(delEid)
    deleteEntities |> clear()
    commit()

    if isMissionRestartRequested
        isMissionRestartRequested = false
        restart_mission(false)

// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw
    fill_rect(0.0, 0.0, SCREEN_SIZE.x, SCREEN_SIZE.y, 0x303030)
    fill_rect(FIELD_POS.x, FIELD_POS.y, FIELD_SIZE.x, FIELD_SIZE.y, 0x000000)
    enable_alpha_blend()
    decs_stage("draw")
    disable_alpha_blend()
    decs_stage("draw_ui")

////////////////////////////////////////////////////////////////////////////////
// ECS Entities
////////////////////////////////////////////////////////////////////////////////

def restart_mission(is_initial: bool)
    if !is_initial
        restart()
    for y in range(0, MAP_SIZE.y)
        for x in range(0, MAP_SIZE.x)
            let cell = character_at(MAP[y], x)
            let pos = float2((float(x) + 0.5) * CELL_SIZE_PX, (float(y) + 0.5) * CELL_SIZE_PX)
            if cell == '1' || cell == '2'
                let isHero = cell == '1'
                make_tank(pos, isHero ? DIR_UP : DIR_DOWN, isHero)
            if cell == 'B' || cell == 'M' || cell == 'T'
                let objTypeIdx = cell == 'B' ? 2 : cell == 'M' ? 3 : 4
                let needCollision = cell != 'T'
                let isForeground = cell == 'T'
                let hp = cell == 'M' ? 10 : 1
                for wx in range(0, 2)
                    for wy in range(0, 2)
                        let shiftPosX = CELL_SIZE_PX * 0.5 * float(wx) - CELL_SIZE_PX * 0.25
                        let shiftPosY = CELL_SIZE_PX * 0.5 * float(wy) - CELL_SIZE_PX * 0.25
                        make_wall(pos + float2(shiftPosX, shiftPosY), objTypeIdx, hp, needCollision, isForeground)
            if cell == 'F'
                make_flag(pos)
    commit()
    var keepAliveTotal = 0
    query <| $ (cc: CmpMissionRuleKeepAliveToWin)
        keepAliveTotal++
    make_mission_state(keepAliveTotal)
    commit()

def make_tank(pos: float2; dir: float2; is_hero: bool)
    let objTypeIdx = is_hero ? 0 : 1
    let team = is_hero ? 1 : 2
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpVisual pos = pos, dir = dir, objTypeIdx = objTypeIdx ]])
        apply_decs_template(cmp, [[ CmpCollision team = team ]])
        apply_decs_template(cmp, [[ CmpMobility dir = dir, speed = 0.0 ]])
        apply_decs_template(cmp, [[ CmpFiring cooldown = 0.0, team = team ]])
        apply_decs_template(cmp, [[ CmpHealth hp = 2 ]])
        if is_hero
            apply_decs_template(cmp, [[ CmpMissionRuleKeepAliveToWin ]])
            apply_decs_template(cmp, [[ CmpControlUser canControl = true ]])
        else
            apply_decs_template(cmp, [[ CmpMissionRuleDestroyAllToWin ]])
            apply_decs_template(cmp, [[ CmpControlBot
                timeNextFire = random_float(randomSeed) * AI_MAX_DELAY_FIRE_SEC,
                timeNextDrive = random_float(randomSeed) * AI_MAX_DELAY_DRIVE_SEC
            ]])

def make_bullet(pos: float2; dir: float2; team: int)
    let objTypeIdx = 6
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpVisual pos = pos, dir = dir, objTypeIdx = objTypeIdx ]])
        apply_decs_template(cmp, [[ CmpCollision team = team, damage = 2 ]])
        apply_decs_template(cmp, [[ CmpMobility dir = dir, speed = SPEED_BULLET ]])

def make_explosion(pos: float2; objTypeIdx: int)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpVisual pos = pos, dir = DIR_RIGHT, objTypeIdx = objTypeIdx ]])
        apply_decs_template(cmp, [[ CmpStaticBG ]])
        apply_decs_template(cmp, [[ CmpLifetime ttl = objTypeIdx == 8 ? 1.0 : 0.25 ]])

def make_wall(pos: float2; objTypeIdx: int; hp: int; needCollision: bool; isForeground: bool)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpVisual pos = pos, dir = DIR_RIGHT, objTypeIdx = objTypeIdx ]])
        apply_decs_template(cmp, [[ CmpHealth hp = hp ]])
        if needCollision
            apply_decs_template(cmp, [[ CmpCollision ]])
        if isForeground
            apply_decs_template(cmp, [[ CmpStaticFG ]])
        else
            apply_decs_template(cmp, [[ CmpStaticBG ]])

def make_flag(pos: float2)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpVisual pos = pos, dir = DIR_RIGHT, objTypeIdx = 5 ]])
        apply_decs_template(cmp, [[ CmpHealth hp = 2 ]])
        apply_decs_template(cmp, [[ CmpCollision ]])
        apply_decs_template(cmp, [[ CmpStaticBG ]])
        apply_decs_template(cmp, [[ CmpMissionRuleKeepAliveToWin ]])

def make_mission_state(keepAliveTotal: int)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[ CmpMissionState keepAliveTotal = keepAliveTotal ]])

////////////////////////////////////////////////////////////////////////////////
// ECS Systems
////////////////////////////////////////////////////////////////////////////////

[decs(stage = input)]
def sys_update_user_control_restart(var r: CmpMissionState)
    if r.missionResult == 0
        return
    if get_key(VK_RETURN)
        isMissionRestartRequested = true

[decs(stage = input)]
def sys_update_user_control_movement(var v: CmpVisual; var m: CmpMobility; var u: CmpControlUser)
    m.speed = 0.0
    if !u.canControl
        return
    for id in keys(arrowKeysTime)
        arrowKeysTime[id] = get_key_down(id) ? get_time_after_start() : get_key_up(id) ? 0.0 : arrowKeysTime[id]
    var latestKeyTime = 0.0
    for id, time in keys(arrowKeysTime), values(arrowKeysTime)
        if time > latestKeyTime
            latestKeyTime = time
            m.speed = SPEED_TANK
            m.dir = id == VK_LEFT ? DIR_LEFT :  id == VK_RIGHT ? DIR_RIGHT : id == VK_UP ? DIR_UP : DIR_DOWN
    v.dir = m.dir

[decs(stage = input)]
def sys_update_user_control_firing(var v: CmpVisual; var f: CmpFiring; var u: CmpControlUser)
    if !u.canControl
        return
    if f.cooldown > 0.0
        f.cooldown = max(0.0, f.cooldown - get_delta_time())
    if get_key(VK_SPACE) && f.cooldown == 0.0
        let t = objTypes[v.objTypeIdx]
        make_bullet(get_bullet_spawn_pos(v.pos, v.dir, t.size), v.dir, f.team)
        f.cooldown = COOLDOWN_FIRE_SEC

[decs(stage = input)]
def sys_update_bot_ai_movement(var v: CmpVisual; var m: CmpMobility; var b: CmpControlBot)
    let dt = get_delta_time()
    if b.timeNextDrive > 0.0
        b.timeNextDrive = max(0.0, b.timeNextDrive - dt)
    if b.timeNextDrive == 0.0
        let rd = random_int(randomSeed) % 4
        m.dir = rd == 0 ? DIR_LEFT : rd == 1 ? DIR_RIGHT : rd == 2 ? DIR_UP : DIR_DOWN
        v.dir = m.dir
        m.speed = SPEED_TANK
        b.timeNextDrive = random_float(randomSeed) * AI_MAX_DELAY_DRIVE_SEC

[decs(stage = input)]
def sys_update_bot_ai_firing(var v: CmpVisual; var f: CmpFiring; var b: CmpControlBot)
    let dt = get_delta_time()
    if f.cooldown > 0.0
        f.cooldown = max(0.0, f.cooldown - dt)
    if b.timeNextFire > 0.0
        b.timeNextFire = max(0.0, b.timeNextFire - dt)
    if b.timeNextFire == 0.0 && f.cooldown == 0.0
        let t = objTypes[v.objTypeIdx]
        make_bullet(get_bullet_spawn_pos(v.pos, v.dir, t.size), v.dir, f.team)
        f.cooldown = COOLDOWN_FIRE_SEC
        b.timeNextFire = random_float(randomSeed) * AI_MAX_DELAY_FIRE_SEC

[decs(stage = update)]
def sys_update_obj_lifetime(var l: CmpLifetime; eid: EntityId)
    l.ttl -= get_delta_time()
    if l.ttl <= 0.0
        deleteEntities |> push(eid)

[decs(stage = update)]
def sys_update_obj_movement_and_interaction(var c: CmpCollision; var v: CmpVisual; var m: CmpMobility; eid: EntityId)
    if m.speed != 0.0
        let t = objTypes[v.objTypeIdx]
        let size = get_rotated_size(t.size, m.dir)
        let expectedPos = v.pos + (v.dir * m.speed * get_delta_time())
        v.pos = clamp(expectedPos, size * 0.5, FIELD_SIZE - size * 0.5)
        let hasMapEdgeCollosion = expectedPos != v.pos
        if hasMapEdgeCollosion && c.damage > 0
            deleteEntities |> push(eid)
            return
        let selfEid = eid
        let box1 = to_box(v.pos, t.size, v.dir)
        query <| $ (cc: CmpCollision; cv: CmpVisual; eid: EntityId)
            let ct = objTypes[cv.objTypeIdx]
            let box2 = to_box(cv.pos, ct.size, cv.dir)
            let needCollisionCheck = selfEid != eid && cc.damage == 0 && (c.damage == 0 || c.team != cc.team)
            let hasCollision = needCollisionCheck && has_collision_on_the_way(v.dir, box1, box2)
            if hasCollision && c.damage == 0
                v.pos = limit_pos_by_collision(v.dir, box1, box2)
            if hasCollision && c.damage > 0 && cc.damage == 0
                query(eid) <| $ (var ch: CmpHealth)
                    let hit = min(ch.hp, c.damage)
                    c.damage -= hit
                    ch.hp -= hit
                    if ch.hp == 0
                        if ct.explosionObjIdx != -1
                            make_explosion(cv.pos, ct.explosionObjIdx)
                        deleteEntities |> push(eid)
                if c.damage == 0
                    deleteEntities |> push(selfEid)

[decs(stage = update)]
def sys_update_mission_state(var r: CmpMissionState)
    if r.missionResult != 0
        return
    var needAllAlive = 0
    var needDestroy = 0
    query <| $ (cc: CmpMissionRuleKeepAliveToWin)
        needAllAlive++
    query <| $ (cc: CmpMissionRuleDestroyAllToWin)
        needDestroy++
    r.missionResult = needDestroy == 0 ? 1 : needAllAlive < r.keepAliveTotal ? 2 : 0
    if (r.missionResult != 0)
        query <| $ (var u: CmpControlUser)
            u.canControl = false

[decs(stage = draw)]
def sys_draw_static_bg(var v: CmpVisual; var _: CmpStaticBG)
    let t = objTypes[v.objTypeIdx]
    var texId = t.texIdx0
    if t.animFreq != 0.0
        texId = get_time_after_start() % (t.animFreq * 2.0) >= t.animFreq ? t.texIdx0 : t.texIdx1
    textures[texId] |> draw_image(FIELD_POS.x + v.pos.x - t.size.x * 0.5, FIELD_POS.y + v.pos.y - t.size.y * 0.5, 0xFFFFFFFF, t.size)

[decs(stage = draw)]
def sys_draw_movable(var v: CmpVisual; var m: CmpMobility)
    let t = objTypes[v.objTypeIdx]
    var texId = t.texIdx0
    if m.speed != 0.0 && t.animFreq != 0.0
        texId = get_time_after_start() % (t.animFreq * 2.0) >= t.animFreq ? t.texIdx0 : t.texIdx1
    let texRect = float4(0.0, 0.0, float(textures[texId].width), float(textures[texId].height))
    let angle = atan2(v.dir.y, v.dir.x)
    textures[texId] |> draw_image_transformed(FIELD_POS.x + v.pos.x, FIELD_POS.y + v.pos.y, texRect, 0xFFFFFFFF, t.size, angle)

[decs(stage = draw)]
def sys_draw_static_fg(var v: CmpVisual; var _: CmpStaticFG)
    let t = objTypes[v.objTypeIdx]
    textures[t.texIdx0] |> draw_image(FIELD_POS.x + v.pos.x - t.size.x * 0.5, FIELD_POS.y + v.pos.y - t.size.y * 0.5, 0xFFFFFFFF, t.size)

[decs(stage = draw_ui)]
def sys_draw_ui(var r: CmpMissionState)
    let isGameOver = r.missionResult != 0
    if isGameOver
        let isVictory = r.missionResult == 1
        set_font_size(50)
        let s = isVictory ? "YOU WIN" : "YOU LOSE"
        let size = get_text_size(s)
        let pos = int2(SCREEN_SIZE * 0.5 - size * 0.5)
        text_out(pos.x + 3, pos.y + 3, s, 0x000000)
        text_out(pos.x, pos.y, s, isVictory ? 0x00FF00 : 0xFF0000)
    set_font_size(12)
    let s = !isGameOver ? "Use arrow keys to drive and [Space] to Fire" : "Press [Enter] to restart the mission"
    let size = get_text_size(s)
    var pos = int2(SCREEN_SIZE.x * 0.5 - size.x * 0.5, FIELD_POS.y * 0.5 - size.y * 0.5)
    text_out(pos.x, pos.y, s, 0x808080)
    pos.y = int(SCREEN_SIZE.y - FIELD_POS.y * 0.5 - size.y * 0.5)
    text_out(pos.x, pos.y, s, 0x808080)

////////////////////////////////////////////////////////////////////////////////
// Utils
////////////////////////////////////////////////////////////////////////////////

def get_rotated_size(size: float2; dir: float2) : float2
    return dir == DIR_UP || dir == DIR_DOWN ? float2(size.y, size.x) : size

def to_box(pos: float2; size: float2; dir: float2): float4
    let halfSize = get_rotated_size(size, dir) * 0.5
    return float4(pos.x - halfSize.x, pos.y - halfSize.y, pos.x + halfSize.x, pos.y + halfSize.y)

def is_box_intersect(a: float4; b: float4): bool
    return a.x < b.z && a.z > b.x && a.y < b.w && a.w > b.y

def has_collision_on_the_way(dir: float2; a: float4; b: float4): bool
    if !is_box_intersect(a, b)
        return false
    return dir.x < 0.0 && a.x < b.z || dir.x > 0.0 && a.z > b.x || dir.y < 0.0 && a.y < b.w || dir.y > 0.0 && a.w > b.y

def limit_pos_by_collision(dir: float2; box: float4; obstacleBox: float4): float2
    let halfSize = float2(box.z - box.x, box.w - box.y) * 0.5
    var pos = float2(box.x + halfSize.x, box.y + halfSize.y)
    if dir.x < 0.0 && box.x > obstacleBox.x
        pos.x = max(box.x, obstacleBox.z) + halfSize.x
    if dir.x > 0.0 && box.z < obstacleBox.z
        pos.x = min(box.z, obstacleBox.x) - halfSize.x
    if dir.y < 0.0 && box.y > obstacleBox.y
        pos.y = max(box.y, obstacleBox.w) + halfSize.y
    if dir.y > 0.0 && box.w < obstacleBox.w
        pos.y = min(box.w, obstacleBox.y) - halfSize.y
    return pos

def get_bullet_spawn_pos(pos: float2; dir: float2; size: float2) : float2
    let x = dir == DIR_UP || dir == DIR_DOWN ? pos.x : dir == DIR_LEFT ? (pos.x - size.x * 0.5) : (pos.x + size.x * 0.5)
    let y = dir == DIR_LEFT || dir == DIR_RIGHT ? pos.y : dir == DIR_UP ? (pos.y - size.x * 0.5) : (pos.y + size.x * 0.5)
    return float2(x, y)
