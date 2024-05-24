#!/bin/bash

git_tok="${1}"
fb_tok="${2}"

branches=('5082e093c2e1fd122b6ecb4d6deefa890e34d68b' '2ff97c5698984fd38069d0f3162da05549830e1a' '491c1cd111bd1ebec274e5a0be89abfebe716a22' '6638a7f8ad970b5cf6836f7d87912c1e7a7ae8da' '11ff7619bdafeb8dc922c2fb246a5bdd36c6a08f' '319adf0a3eb2dbec2aa925676854bbaeca207c9f' 'f8d55703f539389ebd78b225fca9da4568077a43' '5a7b322569b6d4b1681dbba5fd34dcf902c9b8db' 'af6aba8f2be0aeb1de1b735a4c5eb4a2448c5931' 'ca8446da0b8937c3f55fef1ed44e649f8390cbb7' '9b810c5253f7ed2ec80124a1f18e2b719fa241fa' 'c5240a03794a7fe6b8dad539d5ce65c4de3519fd')

main_br(){
	# select rand num from range
	rand_ind="$((RANDOM % ${#branches[@]}))"
	selc_branch="${branches[${rand_ind}]}"
	
	# declare the config file
	source <(curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/config.conf")
	
	# makes it more random
	seed="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
	
	# select frame by number
	all_f="$(curl -sLk  -H "Authorization: Bearer ${git_tok}" "https://api.github.com/repos/fearocanity/ebtrfio-bot/git/trees/${selc_branch}?recursive=1")"
	selc_frame="$(jq .tree[].path <<< "${all_f}" | sed -nE 's|.*/frame_([^\.]*)\.jpg.*|\1|p' | awk -v "s=${seed}" 'BEGIN{srand(s)}rand()<1/NR{i=$0}END{print i}')"
}


nth(){
	# This function aims to convert current frame to time (in seconds)
	#
	# You need to get the exact Frame Rate of a video
	t="${1/[!0-9]/}"
	sec="$(bc -l <<< "scale=2; x = (${t:-1} - 1) / ${img_fps};"' if (length (x) == scale (x) && x != 0) { if (x < 0) print "-",0,-x else print 0,x } else print x')"
 	if [[ "${2}" = "timestamp" ]]  || grep -qE '^-' <<< "${sec}"; then
		sec="$(bc -l <<< "scale=2; x = ${t:-1} / ${img_fps};"' if (length (x) == scale (x) && x != 0) { if (x < 0) print "-",0,-x else print 0,x } else print x')"
	fi
 	[[ "${selc_frame}" =~  [0-9]*\.[0-9]* ]] && sec="$(bc -l <<< "scale=2; ${sec} + 0.145")"
  	secfloat="${sec#*.}" sec="${sec%.*}" sec="${sec:-0}"

	[[ "${secfloat}" =~ ^0[8-9]$ ]] && secfloat="${secfloat#0}"
	secfloat="${secfloat:-0}"
	printf '%01d:%02d:%02d.%02d' "$((sec / 60 / 60 % 60))" "$((sec / 60 % 60))" "$((sec % 60))" "${secfloat}"
	unset sec secfloat
}

scrv3(){
	# This function solves the timings of Subs
	current_time="${1}"
	path_df="$(jq -r .tree[].path <<< "${all_f}" | grep -E "fb/.*ep${episode#0*}.ass|fb/.*ep${episode#0*}_en.ass")"
	subtitle="$(
	awk -F ',' -v curr_time_sc="${current_time}" '/Dialogue:/ {
			split(curr_time_sc, aa, ":");
			curr_time = aa[1]*3600 + aa[2]*60 + aa[3];
			split($2, a, ":");
			start_time = a[1]*3600 + a[2]*60 + a[3];
			split($3, b, ":");
			end_time = b[1]*3600 + b[2]*60 + b[3];
			if (curr_time>=start_time && curr_time<=end_time) {
				c = $0;
				split(c, d, ",");
				split(c, e, ",,");
				f = d[4]","d[5]",";
				g = (f ~ /[a-zA-Z0-9],,/) ? e[3] : e[2];
				gsub(/\r/,"",g);
				gsub(/   /," ",g);
				gsub(/!([a-zA-Z0-9])/,"! \\1",g);
				gsub(/(\\N{\\c&H727571&}|{\\c&HB2B5B2&})/,", ",g);
				gsub(/{([^\x7d]*)}/,"",g);
				if(g ~ /[[:graph:]]\\N/) gsub(/\\N/," ",g);
				gsub(/\\N/,"",g);
				gsub(/\\h/,"",g);
				if (f ~ /[^,]*,sign/) {
					print "【"g"】"
				} else if (f ~ /Signs,,/) {
					print "\""g"\""
				} else if (f ~ /Songs[^,]*,[^,]*,|OP[^,]*,|ED[^,]*,/) {
					print "『"g"』"
				} else {
					print g
				}
			}
		}' <(curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/${path_df}") | \
	awk '!a[$0]++{
			if ($0 ~ /^【.+】$/) aa=aa $0 "\n"; else bb=bb $0 "\n"
		} END {
		print aa bb
		}' | \
	sed '/^[[:blank:]]*$/d;/^$/d'
	)"
	unset current_time
}


main_post(){
	main_br
	scrv3 "$(nth "${selc_frame}")"
	timestamp="$(nth "${selc_frame}" timestamp)"
	
	main_message="$(cat <<-EOF
	[Random Frame]
	Season ${season}, Episode ${episode}, Frame ${selc_frame} (Timestamp: ${timestamp})
	
	${subtitle}
	.
	.
	RNG seed: ${seed}
	EOF
	)"
	
	curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/frames/frame_${selc_frame}.jpg" -o main_frame.jpg
	response="$(curl -sfLX POST --retry 2 --retry-connrefused --retry-delay 7 "https://graph.facebook.com/me/photos?access_token=${fb_tok}&published=1" -F "message=${main_message}" -F "source=@main_frame.jpg")"
	printf '%s\n' "${response}" | grep -Po '(?=[0-9])(.*)(?=\",\")' >> complete.log
	rm main_frame.jpg
}

main_post
