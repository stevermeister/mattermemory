import Foundation

/// Shortcode → unicode for the emoji people actually type. Anything missing
/// stays as `:name:` (custom emoji are resolved through the server instead).
enum Emoji {
    static let map: [String: String] = [
        "smile": "😄", "smiley": "😃", "grinning": "😀", "grin": "😁", "laughing": "😆", "satisfied": "😆", "sweat_smile": "😅", "joy": "😂",
        "rofl": "🤣", "rolling_on_the_floor_laughing": "🤣", "relaxed": "☺️", "blush": "😊", "innocent": "😇", "slightly_smiling_face": "🙂",
        "upside_down_face": "🙃", "wink": "😉", "relieved": "😌", "heart_eyes": "😍", "smiling_face_with_3_hearts": "🥰", "kissing_heart": "😘",
        "kissing": "😗", "yum": "😋", "stuck_out_tongue": "😛", "stuck_out_tongue_winking_eye": "😜", "zany_face": "🤪",
        "stuck_out_tongue_closed_eyes": "😝", "money_mouth_face": "🤑", "hugging_face": "🤗", "hugs": "🤗", "hand_over_mouth": "🤭",
        "shushing_face": "🤫", "thinking": "🤔", "thinking_face": "🤔", "zipper_mouth_face": "🤐", "raised_eyebrow": "🤨", "neutral_face": "😐",
        "expressionless": "😑", "no_mouth": "😶", "smirk": "😏", "unamused": "😒", "roll_eyes": "🙄", "grimacing": "😬", "lying_face": "🤥",
        "pensive": "😔", "sleepy": "😪", "drooling_face": "🤤", "sleeping": "😴", "mask": "😷", "face_with_thermometer": "🤒",
        "face_with_head_bandage": "🤕", "nauseated_face": "🤢", "vomiting_face": "🤮", "sneezing_face": "🤧", "hot_face": "🥵", "cold_face": "🥶",
        "woozy_face": "🥴", "dizzy_face": "😵", "exploding_head": "🤯", "cowboy_hat_face": "🤠", "partying_face": "🥳", "sunglasses": "😎",
        "nerd_face": "🤓", "monocle_face": "🧐", "confused": "😕", "worried": "😟", "slightly_frowning_face": "🙁", "frowning_face": "☹️",
        "open_mouth": "😮", "hushed": "😯", "astonished": "😲", "flushed": "😳", "pleading_face": "🥺", "frowning": "😦", "anguished": "😧",
        "fearful": "😨", "cold_sweat": "😰", "disappointed_relieved": "😥", "cry": "😢", "sob": "😭", "scream": "😱", "confounded": "😖",
        "persevere": "😣", "disappointed": "😞", "sweat": "😓", "weary": "😩", "tired_face": "😫", "yawning_face": "🥱", "triumph": "😤",
        "rage": "😡", "pout": "😡", "angry": "😠", "cursing_face": "🤬", "smiling_imp": "😈", "imp": "👿", "skull": "💀",
        "skull_and_crossbones": "☠️", "poop": "💩", "hankey": "💩", "clown_face": "🤡", "ghost": "👻", "alien": "👽", "robot": "🤖",
        "robot_face": "🤖", "smiley_cat": "😺", "smile_cat": "😸", "joy_cat": "😹", "heart_eyes_cat": "😻", "see_no_evil": "🙈",
        "hear_no_evil": "🙉", "speak_no_evil": "🙊", "kiss": "💋", "love_letter": "💌", "heart": "❤️", "orange_heart": "🧡", "yellow_heart": "💛",
        "green_heart": "💚", "blue_heart": "💙", "purple_heart": "💜", "black_heart": "🖤", "white_heart": "🤍", "broken_heart": "💔",
        "heavy_heart_exclamation": "❣️", "two_hearts": "💕", "sparkling_heart": "💖", "heartpulse": "💗", "heartbeat": "💓",
        "revolving_hearts": "💞", "cupid": "💘", "gift_heart": "💝", "100": "💯", "anger": "💢", "boom": "💥", "collision": "💥", "dizzy": "💫",
        "sweat_drops": "💦", "dash": "💨", "hole": "🕳️", "bomb": "💣", "speech_balloon": "💬", "thought_balloon": "💭", "zzz": "💤", "wave": "👋",
        "raised_back_of_hand": "🤚", "raised_hand_with_fingers_splayed": "🖐️", "hand": "✋", "raised_hand": "✋", "vulcan_salute": "🖖",
        "ok_hand": "👌", "pinching_hand": "🤏", "v": "✌️", "crossed_fingers": "🤞", "love_you_gesture": "🤟", "metal": "🤘", "call_me_hand": "🤙",
        "point_left": "👈", "point_right": "👉", "point_up_2": "👆", "middle_finger": "🖕", "point_down": "👇", "point_up": "☝️", "+1": "👍",
        "thumbsup": "👍", "-1": "👎", "thumbsdown": "👎", "fist": "✊", "fist_raised": "✊", "facepunch": "👊", "punch": "👊",
        "fist_oncoming": "👊", "fist_left": "🤛", "fist_right": "🤜", "clap": "👏", "raised_hands": "🙌", "open_hands": "👐",
        "palms_up_together": "🤲", "handshake": "🤝", "pray": "🙏", "writing_hand": "✍️", "nail_care": "💅", "selfie": "🤳", "muscle": "💪",
        "mechanical_arm": "🦾", "eyes": "👀", "eye": "👁️", "brain": "🧠", "tongue": "👅", "lips": "👄", "ear": "👂", "nose": "👃", "baby": "👶",
        "boy": "👦", "girl": "👧", "man": "👨", "woman": "👩", "older_man": "👴", "older_woman": "👵", "cop": "👮", "police_officer": "👮",
        "construction_worker": "👷", "guard": "💂", "detective": "🕵️", "santa": "🎅", "angel": "👼", "person_facepalming": "🤦", "facepalm": "🤦",
        "man_facepalming": "🤦‍♂️", "woman_facepalming": "🤦‍♀️", "shrug": "🤷", "person_shrugging": "🤷", "man_shrugging": "🤷‍♂️",
        "woman_shrugging": "🤷‍♀️", "bow": "🙇", "raising_hand": "🙋", "no_good": "🙅", "ok_woman": "🙆", "information_desk_person": "💁",
        "dancer": "💃", "man_dancing": "🕺", "walking": "🚶", "runner": "🏃", "running": "🏃", "couple": "👫", "family": "👪", "dog": "🐶",
        "cat": "🐱", "mouse": "🐭", "hamster": "🐹", "rabbit": "🐰", "fox_face": "🦊", "bear": "🐻", "panda_face": "🐼", "koala": "🐨",
        "tiger": "🐯", "lion": "🦁", "cow": "🐮", "pig": "🐷", "frog": "🐸", "monkey_face": "🐵", "monkey": "🐒", "chicken": "🐔", "penguin": "🐧",
        "bird": "🐦", "hatching_chick": "🐣", "baby_chick": "🐤", "duck": "🦆", "eagle": "🦅", "owl": "🦉", "bat": "🦇", "wolf": "🐺", "boar": "🐗",
        "horse": "🐴", "unicorn": "🦄", "bee": "🐝", "honeybee": "🐝", "bug": "🐛", "butterfly": "🦋", "snail": "🐌", "beetle": "🪲", "ant": "🐜",
        "spider": "🕷️", "turtle": "🐢", "snake": "🐍", "lizard": "🦎", "t-rex": "🦖", "octopus": "🐙", "squid": "🦑", "shrimp": "🦐", "crab": "🦀",
        "fish": "🐟", "tropical_fish": "🐠", "blowfish": "🐡", "shark": "🦈", "dolphin": "🐬", "whale": "🐳", "crocodile": "🐊", "elephant": "🐘",
        "camel": "🐫", "giraffe": "🦒", "goat": "🐐", "sheep": "🐑", "dragon": "🐉", "rooster": "🐓", "turkey": "🦃", "dove": "🕊️", "rat": "🐀",
        "bouquet": "💐", "cherry_blossom": "🌸", "rose": "🌹", "hibiscus": "🌺", "sunflower": "🌻", "blossom": "🌼", "tulip": "🌷",
        "seedling": "🌱", "evergreen_tree": "🌲", "deciduous_tree": "🌳", "palm_tree": "🌴", "cactus": "🌵", "herb": "🌿", "shamrock": "☘️",
        "four_leaf_clover": "🍀", "maple_leaf": "🍁", "fallen_leaf": "🍂", "leaves": "🍃", "mushroom": "🍄", "apple": "🍎", "green_apple": "🍏",
        "pear": "🍐", "tangerine": "🍊", "lemon": "🍋", "banana": "🍌", "watermelon": "🍉", "grapes": "🍇", "strawberry": "🍓", "cherries": "🍒",
        "peach": "🍑", "pineapple": "🍍", "kiwi_fruit": "🥝", "avocado": "🥑", "tomato": "🍅", "eggplant": "🍆", "corn": "🌽", "hot_pepper": "🌶️",
        "carrot": "🥕", "potato": "🥔", "bread": "🍞", "croissant": "🥐", "cheese": "🧀", "egg": "🥚", "bacon": "🥓", "hamburger": "🍔",
        "fries": "🍟", "pizza": "🍕", "hotdog": "🌭", "taco": "🌮", "burrito": "🌯", "sandwich": "🥪", "popcorn": "🍿", "salad": "🥗", "ramen": "🍜",
        "spaghetti": "🍝", "sushi": "🍣", "rice": "🍚", "curry": "🍛", "bento": "🍱", "cookie": "🍪", "cake": "🍰", "birthday": "🎂",
        "cupcake": "🧁", "doughnut": "🍩", "icecream": "🍦", "chocolate_bar": "🍫", "candy": "🍬", "lollipop": "🍭", "honey_pot": "🍯",
        "coffee": "☕", "tea": "🍵", "beer": "🍺", "beers": "🍻", "wine_glass": "🍷", "cocktail": "🍸", "tropical_drink": "🍹", "champagne": "🍾",
        "clinking_glasses": "🥂", "tumbler_glass": "🥃", "cup_with_straw": "🥤", "milk_glass": "🥛", "baby_bottle": "🍼", "fork_and_knife": "🍴",
        "earth_africa": "🌍", "earth_americas": "🌎", "earth_asia": "🌏", "globe_with_meridians": "🌐", "world_map": "🗺️", "house": "🏠",
        "office": "🏢", "hospital": "🏥", "bank": "🏦", "hotel": "🏨", "school": "🏫", "factory": "🏭", "car": "🚗", "red_car": "🚗", "taxi": "🚕",
        "bus": "🚌", "truck": "🚚", "tractor": "🚜", "bike": "🚲", "rocket": "🚀", "airplane": "✈️", "helicopter": "🚁", "ship": "🚢",
        "anchor": "⚓", "fuelpump": "⛽", "construction": "🚧", "traffic_light": "🚥", "vertical_traffic_light": "🚦", "stop_sign": "🛑",
        "hourglass": "⌛", "hourglass_flowing_sand": "⏳", "watch": "⌚", "alarm_clock": "⏰", "stopwatch": "⏱️", "clock1": "🕐", "clock12": "🕛",
        "sunny": "☀️", "full_moon": "🌕", "new_moon": "🌑", "crescent_moon": "🌙", "star": "⭐", "star2": "🌟", "stars": "🌠", "sparkles": "✨",
        "cloud": "☁️", "partly_sunny": "⛅", "zap": "⚡", "fire": "🔥", "snowflake": "❄️", "snowman": "⛄", "umbrella": "☔", "ocean": "🌊",
        "rainbow": "🌈", "jack_o_lantern": "🎃", "christmas_tree": "🎄", "fireworks": "🎆", "tada": "🎉", "confetti_ball": "🎊", "balloon": "🎈",
        "gift": "🎁", "trophy": "🏆", "medal_sports": "🏅", "first_place_medal": "🥇", "second_place_medal": "🥈", "third_place_medal": "🥉",
        "soccer": "⚽", "basketball": "🏀", "football": "🏈", "baseball": "⚾", "tennis": "🎾", "8ball": "🎱", "ping_pong": "🏓", "golf": "⛳",
        "ski": "🎿", "dart": "🎯", "video_game": "🎮", "game_die": "🎲", "chess_pawn": "♟️", "jigsaw": "🧩", "art": "🎨", "musical_note": "🎵",
        "notes": "🎶", "microphone": "🎤", "headphones": "🎧", "guitar": "🎸", "drum": "🥁", "clapper": "🎬", "movie_camera": "🎥", "camera": "📷",
        "tv": "📺", "radio": "📻", "iphone": "📱", "computer": "💻", "desktop_computer": "🖥️", "keyboard": "⌨️", "printer": "🖨️",
        "floppy_disk": "💾", "cd": "💿", "phone": "☎️", "telephone": "☎️", "battery": "🔋", "electric_plug": "🔌", "bulb": "💡",
        "flashlight": "🔦", "candle": "🕯️", "moneybag": "💰", "dollar": "💵", "euro": "💶", "credit_card": "💳", "chart": "💹", "email": "📧",
        "e-mail": "📧", "envelope": "✉️", "inbox_tray": "📥", "outbox_tray": "📤", "package": "📦", "mailbox": "📫", "memo": "📝", "pencil": "📝",
        "pencil2": "✏️", "briefcase": "💼", "file_folder": "📁", "open_file_folder": "📂", "date": "📅", "calendar": "📆",
        "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉", "bar_chart": "📊", "clipboard": "📋", "pushpin": "📌",
        "round_pushpin": "📍", "paperclip": "📎", "straight_ruler": "📏", "scissors": "✂️", "lock": "🔒", "unlock": "🔓", "key": "🔑",
        "hammer": "🔨", "wrench": "🔧", "hammer_and_wrench": "🛠️", "gear": "⚙️", "nut_and_bolt": "🔩", "link": "🔗", "chains": "⛓️",
        "toolbox": "🧰", "magnet": "🧲", "test_tube": "🧪", "microscope": "🔬", "telescope": "🔭", "satellite": "📡", "syringe": "💉", "pill": "💊",
        "bell": "🔔", "no_bell": "🔕", "loudspeaker": "📢", "mega": "📣", "mag": "🔍", "mag_right": "🔎", "book": "📖", "books": "📚",
        "bookmark": "🔖", "newspaper": "📰", "label": "🏷️", "shield": "🛡️", "crown": "👑", "gem": "💎", "ring": "💍", "coffin": "⚰️",
        "bath": "🛀", "shower": "🚿", "warning": "⚠️", "no_entry": "⛔", "no_entry_sign": "🚫", "x": "❌", "negative_squared_cross_mark": "❎",
        "heavy_check_mark": "✔️", "white_check_mark": "✅", "ballot_box_with_check": "☑️", "heavy_multiplication_x": "✖️",
        "heavy_plus_sign": "➕", "heavy_minus_sign": "➖", "heavy_division_sign": "➗", "question": "❓", "grey_question": "❔",
        "grey_exclamation": "❕", "exclamation": "❗", "heavy_exclamation_mark": "❗", "bangbang": "‼️", "interrobang": "⁉️", "recycle": "♻️",
        "trident": "🔱", "beginner": "🔰", "o": "⭕", "arrow_right": "➡️", "arrow_left": "⬅️", "arrow_up": "⬆️", "arrow_down": "⬇️",
        "arrow_upper_right": "↗️", "arrow_lower_right": "↘️", "arrows_counterclockwise": "🔄", "arrow_forward": "▶️", "arrow_backward": "◀️",
        "fast_forward": "⏩", "rewind": "⏪", "repeat": "🔁", "top": "🔝", "soon": "🔜", "back": "🔙", "new": "🆕", "ok": "🆗", "cool": "🆒",
        "free": "🆓", "sos": "🆘", "up": "🆙", "copyright": "©️", "registered": "®️", "tm": "™️", "hash": "#️⃣", "zero": "0️⃣", "one": "1️⃣",
        "two": "2️⃣", "three": "3️⃣", "four": "4️⃣", "five": "5️⃣", "six": "6️⃣", "seven": "7️⃣", "eight": "8️⃣", "nine": "9️⃣",
        "keycap_ten": "🔟", "red_circle": "🔴", "orange_circle": "🟠", "yellow_circle": "🟡", "green_circle": "🟢", "large_blue_circle": "🔵",
        "purple_circle": "🟣", "black_circle": "⚫", "white_circle": "⚪", "red_square": "🟥", "green_square": "🟩", "blue_square": "🟦",
        "black_square": "⬛", "white_square": "⬜", "small_blue_diamond": "🔹", "small_orange_diamond": "🔸", "large_blue_diamond": "🔷",
        "large_orange_diamond": "🔶", "black_flag": "🏴", "white_flag": "🏳️", "checkered_flag": "🏁", "triangular_flag_on_post": "🚩",
        "rainbow_flag": "🏳️‍🌈", "eyeglasses": "👓", "necktie": "👔", "shirt": "👕", "tshirt": "👕", "jeans": "👖", "dress": "👗", "bikini": "👙",
        "high_heel": "👠", "athletic_shoe": "👟", "tophat": "🎩", "mortar_board": "🎓", "handbag": "👜", "pouch": "👝", "lipstick": "💄",
        "sparkle": "❇️", "eight_spoked_asterisk": "✳️", "wheelchair": "♿", "mens": "🚹", "womens": "🚺", "restroom": "🚻", "baby_symbol": "🚼",
        "wc": "🚾", "potable_water": "🚰", "medal": "🏅", "clock": "🕰️", "calendar_spiral": "🗓️", "spiral_notepad": "🗒️", "wastebasket": "🗑️",
        "card_index_dividers": "🗂️", "dagger": "🗡️", "crossed_swords": "⚔️", "bow_and_arrow": "🏹", "sunrise": "🌅", "city_sunset": "🌇",
        "night_with_stars": "🌃", "bridge_at_night": "🌉", "mountain": "⛰️", "volcano": "🌋", "desert": "🏜️", "beach_umbrella": "🏖️",
        "island": "🏝️", "tent": "⛺", "stadium": "🏟️", "classical_building": "🏛️", "european_castle": "🏰", "statue_of_liberty": "🗽",
        "tokyo_tower": "🗼", "church": "⛪", "mosque": "🕌", "synagogue": "🕍", "kaaba": "🕋", "fountain": "⛲", "bullettrain_front": "🚅",
        "train": "🚋", "metro": "🚇", "tram": "🚊", "station": "🚉", "police_car": "🚓", "ambulance": "🚑", "fire_engine": "🚒", "minibus": "🚐",
        "articulated_lorry": "🚛", "motorcycle": "🏍️", "scooter": "🛴", "sailboat": "⛵", "speedboat": "🚤", "seat": "💺", "eyes_wide": "👀",
        "man_technologist": "👨‍💻", "woman_technologist": "👩‍💻", "technologist": "🧑‍💻", "man_office_worker": "👨‍💼",
        "woman_office_worker": "👩‍💼", "mage": "🧙", "superhero": "🦸", "zombie": "🧟", "ninja": "🥷", "nail_polish": "💅", "mechanical_leg": "🦿",
        "leg": "🦵", "foot": "🦶", "bone": "🦴", "tooth": "🦷", "coffin_open": "⚰️", "speaking_head": "🗣️", "bust_in_silhouette": "👤",
        "busts_in_silhouette": "👥", "footprints": "👣", "smiling_face_with_tear": "🥲", "disguised_face": "🥸", "pinched_fingers": "🤌",
        "salute": "🫡", "saluting_face": "🫡", "melting_face": "🫠", "face_holding_back_tears": "🥹", "dotted_line_face": "🫥",
        "face_with_open_eyes_and_hand_over_mouth": "🫢", "face_with_peeking_eye": "🫣", "heart_hands": "🫶",
        "index_pointing_at_the_viewer": "🫵", "white_heart_suit": "🤍", "mending_heart": "❤️‍🩹", "heart_on_fire": "❤️‍🔥", "pleading": "🥺",
        "smiling_face_with_hearts": "🥰", "star-struck": "🤩", "star_struck": "🤩", "face_with_symbols_on_mouth": "🤬", "face_vomiting": "🤮",
        "face_with_raised_eyebrow": "🤨", "face_with_hand_over_mouth": "🤭", "face_with_monocle": "🧐", "shrug_male": "🤷‍♂️",
        "shrug_female": "🤷‍♀️", "male_sign": "♂️", "female_sign": "♀️", "infinity": "♾️", "gemini": "♊", "check_mark": "✔️",
        "cross_mark": "❌", "large_green_circle": "🟢", "large_red_circle": "🔴", "large_yellow_circle": "🟡", "eyes_right": "👀",
        "bug_beetle": "🐛",
    ]

    private static let shortcodeRegex = try! NSRegularExpression(pattern: ":([a-zA-Z0-9_+\\-]+):")

    /// Replaces `:shortcode:` with unicode where known. Custom emoji names are left intact.
    static func replaceShortcodes(in text: String, custom: Set<String> = []) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in shortcodeRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            guard !custom.contains(name), let e = unicode(name) else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += e
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static let skinTones: [(String, String)] = [
        ("_light_skin_tone", "\u{1F3FB}"), ("_medium_light_skin_tone", "\u{1F3FC}"), ("_medium_skin_tone", "\u{1F3FD}"),
        ("_medium_dark_skin_tone", "\u{1F3FE}"), ("_dark_skin_tone", "\u{1F3FF}"),
    ]

    static func unicode(_ name: String) -> String? {
        if let e = map[name] { return e }
        for (suffix, modifier) in skinTones where name.hasSuffix(suffix) {
            if let base = map[String(name.dropLast(suffix.count))] {
                // Strip a variation selector before applying the modifier.
                return base.replacingOccurrences(of: "\u{FE0F}", with: "") + modifier
            }
        }
        return nil
    }
}
