AddCSLuaFile()

if SERVER then return end

local PREFIX = "<<"

local JAVASCRIPT = [[
	var SILENCE = 0;
	var INITIAL_OFFSET = 44;
	var LOWEST_PITCH = 0.8;
	var HIGHEST_PITCH = 1.2;

	var wave_file_path = "../data/animalese.wav";
	var wav_seconds_per_letter = 0.15;
	var out_seconds_per_letter = 0.075;
	var AudioContext = window.AudioContext || window.webkitAudioContext;
	var audio = new AudioContext();
	var alphabet_buffer;

	function download_buffer(url, callback) {
		var request = new XMLHttpRequest();
		request.open("GET", url);
		request.responseType = "arraybuffer";
		request.send();
		request.onload = function() {
			audio.decodeAudioData(
				request.response,
				function(buffer) {
					callback(buffer);
				},
				function(err) {
				}
			);
		};
	}

	download_buffer(wave_file_path, function(buffer) {
		alphabet_buffer = buffer;
	})

	function calculate_starting_offset(char) {
		if (alphabet_buffer === undefined) { return; }

		var char_offset = char.charCodeAt(0) - 'A'.charCodeAt(0);
		var wav_samples_per_letter = alphabet_buffer.sampleRate * wav_seconds_per_letter;
		return wav_samples_per_letter * char_offset;
	}

	function fill_buffer_with_silence(buffer) {
		for (var chan_idx = 0; chan_idx < buffer.numberOfChannels; ++chan_idx) {
			var chan_buffer = buffer.getChannelData(chan_idx);
			for (var i = 0; i < buffer.length; ++i) {
				chan_buffer[i] = SILENCE;
			}
		}

		return buffer;
	}

	function create_char_audio_buffer(char, pitch) {
		if (alphabet_buffer === undefined) { return; }

		if (pitch < LOWEST_PITCH) {
			pitch = LOWEST_PITCH;
		} else if (pitch > HIGHEST_PITCH) {
			pitch = HIGHEST_PITCH;
		}

		var char_frame_count = Math.floor(alphabet_buffer.sampleRate * out_seconds_per_letter);
		var char_audio_buffer = audio.createBuffer(
			alphabet_buffer.numberOfChannels,
			char_frame_count,
			alphabet_buffer.sampleRate
		);

		if (char < 'A' || char > 'Z') {
			return fill_buffer_with_silence(char_audio_buffer);
		}

		var start_offset = calculate_starting_offset(char);
		for (var channel = 0; channel < char_audio_buffer.numberOfChannels; ++channel) {
			var chan_buffer = char_audio_buffer.getChannelData(channel);
			var wav_chan_arr_buffer = alphabet_buffer.getChannelData(channel);
			for (var i = 0; i < char_frame_count; ++i) {
				chan_buffer[i] = wav_chan_arr_buffer[INITIAL_OFFSET + start_offset + Math.floor(i * pitch)];
			}
		}

		return char_audio_buffer;
	}

	function get_char_audio(char, pitch) {
		if (alphabet_buffer === undefined || char > 1) { return; }

		char = char.toUpperCase();
		return create_char_audio_buffer(char, pitch);
	}


	function concat_audio_buffers(buffers) {
		var min_num_of_channels = buffers
			.map(function(buf) { return buf.numberOfChannels; })
			.reduce(function(a, b) { return Math.min(a, b); });

		var total_duration = buffers
			.map(function(buf) { return buf.duration; })
			.reduce(function(a, b) { return a + b; });

		var mega_buffer = audio.createBuffer(
			min_num_of_channels,
			audio.sampleRate * total_duration,
			audio.sampleRate
		);

		if (mega_buffer.copyTochannel == null) {
			mega_buffer.copyToChannel = function(source, channelNumber, startInChannel) {
				var clipped = source.subarray(0, Math.min(source.length, this.length - (startInChannel|0)));
				this.getChannelData(channelNumber|0).set(clipped, startInChannel|0);
			};
		}

		for (var chan_idx = 0; chan_idx < min_num_of_channels; ++chan_idx) {
			var dataIdx = 0;
			for (var buffer_index = 0; buffer_index < buffers.length; buffer_index++) {
				var buffer = buffers[buffer_index];
				mega_buffer.copyToChannel(buffer.getChannelData(chan_idx), chan_idx, dataIdx);
				dataIdx += buffer.length;
			}
		}

		return mega_buffer;
	}

	window.IsCEFBranch = !(Array.from === undefined);

	window.PlayAnimalese = function(text, pitch, volume_level) {
		try {
			var buffers = [];
			for (var i = 0; i < text.length; i++) {
				var char_buf = get_char_audio(text.charAt(i), pitch);
				if (char_buf != null) {
					buffers.push(char_buf);
				}
			}

			const source = audio.createBufferSource();
			source.buffer = concat_audio_buffers(buffers);

			var volume;
			if (audio.createGain != null) {
				volume = audio.createGain();
			} else {
				volume = audio.createGainNode();
			}

			volume.gain.linearRampToValueAtTime(volume_level, 0);

			source.connect(volume);
			volume.connect(audio.destination);

			if (source.start) {
				source.start();
			} else {
				source.noteOn(0);
			}
		} catch (err) {
			animalese.Print("err: " + err);
		}
	}
]]

local html
local text_input, pitch_input, volume_input = "", 1, 0
local ready = false
local function init_animalese()
	if IsValid(html) then return true end

	ready = false

	html = vgui.Create("DHTML")
	html:SetAllowLua(false)
	html:SetVisible(true)
	html:SetPos(ScrW(), ScrH())
	html:SetSize(1, 1)
	html:ParentToHUD()
	html:SetAlpha(1)
	html:SetPaintedManually(true)
	html:SetVerticalScrollbarEnabled(false)

	if not file.Exists("animalese.wav", "DATA") or not file.Exists("animalese_html.txt", "DATA") then
		http.Fetch("https://raw.githubusercontent.com/Earu/gm_animalese/main/external/animalese.wav", function(body)
			file.Write("animalese.wav", body)
			file.Write("animalese_html.txt", ("<html><body><script>%s</script></body></html>"):format(JAVASCRIPT))

			html:OpenURL("asset://garrysmod/data/animalese_html.txt")

			function html:OnFinishLoadingDocument()
				html:AddFunction("animalese", "GetInput", function()
					return text_input, pitch_input, volume_input
				end)
				html:AddFunction("animalese", "Print", print)
				ready = true
			end
		end)
	else
		html:OpenURL("asset://garrysmod/data/animalese_html.txt")

		function html:OnFinishLoadingDocument()
			html:AddFunction("animalese", "GetInput", function()
				return text_input, pitch_input, volume_input
			end)
			html:AddFunction("animalese", "Print", print)
			ready = true
		end
	end

	return false
end

local numbers = {
	[1] = "one", [2] = "two", [3] = "three", [4] = "four", [5] = "five",
	[6] = "six", [7] = "seven", [8] = "eight", [9] = "nine", [0] = "zero"
}

local function sanitize_text(text)
	return text
		:gsub("[0-9]", function(n) return numbers[tonumber(n)] or "" end)
		:gsub("[^a-zA-Z]", " ")
		:JavascriptSafe()
		:Trim()
end

local function string_hash(text)
	local counter = 1
	local len = #text
	for i = 1, len, 3 do
		counter =
			math.fmod(counter * 8161, 4294967279) + -- 2^32 - 17: Prime!
			(text:byte(i) * 16776193) +
			((text:byte(i + 1) or (len - i + 256)) * 8372226) +
			((text:byte(i + 2) or (len - i + 256)) * 3932164)
	end

	return math.fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

local function compute_ply_pitch(ply)
	local hash = string_hash(ply:SteamID()) % 40
	return (80 + hash) / 100
end

local ANIM_ENABLE = CreateConVar("animalese_enable", "1", FCVAR_ARCHIVE, "Enable/disable animalese", 0, 1)
local ANIM_DISTANCE = CreateConVar("animalese_distance", "500", FCVAR_ARCHIVE, "Max distance where animalese can be heard", 1, 2e9)
local ANIM_ALL_MSG = CreateConVar("animalese_all_msgs", "0", FCVAR_ARCHIVE, "Enable/disable animalese for all messages", 0, 1)

local function should_play(text)
	if not ANIM_ENABLE:GetBool() then return false end
	if ANIM_ALL_MSG:GetBool() then return true end

	return text:StartWith(PREFIX)
end

local function play_animalese(ply, text)
	if not should_play(text) then return false end

	local focus_cvar = GetConVar("snd_mute_losefocus")
	if (focus_cvar:GetBool() and system.HasFocus()) or not focus_cvar:GetBool() then
		local dist = ply:EyePos():Distance(LocalPlayer():EyePos())
		local volume = math.max(0, GetConVar("volume"):GetFloat() * (1 - dist / ANIM_DISTANCE:GetInt()))
		text_input, pitch_input, volume_input = sanitize_text(text), compute_ply_pitch(ply), volume
		html:RunJavascript(([[
			if (window.IsCEFBranch) {
				animalese.GetInput(window.PlayAnimalese);
			} else {
				window.PlayAnimalese(%q, %f, %f);
			}
		]]):format(text_input, pitch_input, volume_input))
	end

	return true
end

local ANIMALESE_COLOR = Color(255, 95, 154)
local WHITE_COLOR = Color(255, 255, 255)
local function display_msg(ply, text, is_team, is_dead, is_local)
	local msg_components = {}
	if EasyChat then
		if is_dead then
			EasyChat.AddDeadTag(msg_components)
		end

		if is_team then
			EasyChat.AddTeamTag(msg_components)
		end

		if is_local then
			EasyChat.AddLocalTag(msg_components)
		end
	end

	table.insert(msg_components, ANIMALESE_COLOR)
	table.insert(msg_components, "[animalese/")
	table.insert(msg_components, WHITE_COLOR)
	table.insert(msg_components, ply)
	table.insert(msg_components, ANIMALESE_COLOR)
	table.insert(msg_components, "] - " .. text:gsub("^" .. PREFIX:PatternSafe(), ""))

	chat.AddText(unpack(msg_components))

	if cookie.GetNumber("animalese_tutorial", 0) == 0 then
		cookie.Set("animalese_tutorial", "1")
		chat.AddText(ANIMALESE_COLOR, "\n===============\n", WHITE_COLOR,
			"To speak in ", ANIMALESE_COLOR, "animalese", WHITE_COLOR, " type ", ANIMALESE_COLOR, PREFIX, WHITE_COLOR,
			" followed by the text you want to speak.\n", ANIMALESE_COLOR, "===============")
	end
end

local queue_id = 0
hook.Add("OnPlayerChat", "animalese", function(ply, text, is_team, is_dead, is_local)
	local available = init_animalese()
	if not available or not ready and should_play(ply, text) then
		local hook_name = ("animalese_queue_[%d]"):format(queue_id)
		queue_id = queue_id + 1

		hook.Add("Think", hook_name, function()
			if not ready then return end

			play_animalese(ply, text)
			hook.Remove("Think", hook_name)
		end)

		display_msg(ply, text, is_team, is_dead, is_local)
		return true
	end

	local playing = play_animalese(ply, text)
	if playing then
		display_msg(ply, text, is_team, is_dead, is_local)
		return true
	end
end)

hook.Add("ChatsoundsShouldPlay", "animalese", function(ply, text)
	if should_play(text) then return false end
end)

-- this is a hack to detect stopsound
hook.Add("InitPostEntity", "animalese.StopSoundHack", function()
	local snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
	snd:PlayEx(0, 100)

	hook.Add("Think", "animalese.StopSoundhack", function()
		if not snd or not snd:IsPlaying() then
			snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
			snd:PlayEx(0, 100)

			-- remove the panel, so it creates another
			if IsValid(html) then
				html:Remove()
			end
		end
	end)
end)