#!/bin/bash

git_tok="${1}"
fb_tok="${2}"

branches=('5082e093c2e1fd122b6ecb4d6deefa890e34d68b' '2ff97c5698984fd38069d0f3162da05549830e1a' '491c1cd111bd1ebec274e5a0be89abfebe716a22' '6638a7f8ad970b5cf6836f7d87912c1e7a7ae8da' '11ff7619bdafeb8dc922c2fb246a5bdd36c6a08f' '319adf0a3eb2dbec2aa925676854bbaeca207c9f' 'f8d55703f539389ebd78b225fca9da4568077a43' '5a7b322569b6d4b1681dbba5fd34dcf902c9b8db' 'af6aba8f2be0aeb1de1b735a4c5eb4a2448c5931' 'ca8446da0b8937c3f55fef1ed44e649f8390cbb7' '9b810c5253f7ed2ec80124a1f18e2b719fa241fa' 'c5240a03794a7fe6b8dad539d5ce65c4de3519fd')

rand_gen(){
    od -vAn -N4 -tu4 < /dev/urandom | tr -d ' \n' | fold -w1 | shuf | tr -d ' \n'
}

main_br(){
    # select rand num from range
    [[ -z "${selc_branch}" ]] && selc_branch="$(awk -v s="$(rand_gen)" '{n=split($0,i," ");srand(s);x=int(1+rand()*n);print i[x]}' <<< "${branches[*]}")"
    # declare the config file
    source <(curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/config.conf")
    
    # makes it more random
    [[ -z "${seed}" ]] && seed="$(rand_gen)"
    
    # select frame by number
    [[ -z "${all_f}" ]] && all_f="$(curl -sLk  -H "Authorization: Bearer ${git_tok}" "https://api.github.com/repos/fearocanity/ebtrfio-bot/git/trees/${selc_branch}?recursive=1")"
    if [[ -z "${selc_frame}" ]]; then
        selc_frame="$(jq .tree[].path <<< "${all_f}" | sed -nE 's|.*/frame_(.*)\.jpg.*|\1|p' | awk -v s="${seed}" 'BEGIN{srand(s)}{++n;if(rand()<1/n)l=$0}END{print l}')"
    else
        selc_frame_old="${selc_frame}"
        selc_frame="$(( ${selc_frame%.*} + $(shuf -i 7-25 -n 1) ))"
    fi
}

nth(){
    # This function aims to convert current frame to time (in seconds)
    #
    # You need to get the exact Frame Rate of a video
    t="${1/[!0-9.]/}"
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
                    print "[sign]"g"[/sign]"
                } else if (f ~ /Signs,,/) {
                    print "[signs]"g"[/signs]"
                } else if (f ~ /Songs[^,]*,[^,]*,|OP[^,]*,|ED[^,]*,/) {
                    print "[song]"g"[/song]"
                } else {
                    print g
                }
            }
        }' <(curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/${path_df}") | \
    awk '!a[$0]++{
            if ($0 ~ /^\[sig(n|ns)\]/) aa=aa $0 "\n"; else bb=bb $0 "\n"
        } END {
        print aa bb
        }' | \
    sed '/^[[:blank:]]*$/d;/^$/d'
    )"
    unset current_time
}

rand_func(){ od -vAn -N2 -tu2 < /dev/urandom | tr -dc '0-9' ;}
rand_range(){ awk -v "a=200" -v "b=600" -v "c=$(rand_func)" 'BEGIN{srand();print int(a+(rand() - c % c)*(b-a+1))}' ;}

random_crop(){
    crop_width="$(rand_range)"
    crop_height="$(rand_range)"
    image_width="$(identify -format '%w' "${1}")"
    image_height="$(identify -format '%h' "${1}")"
    crop_x="$(($(rand_func) % (image_width - crop_width)))"
    crop_y="$(($(rand_func) % (image_height - crop_height)))"
    convert "${1}" -crop "${crop_width}x${crop_height}+${crop_x}+${crop_y}" output_image.jpg
    msg_rc="Random Crop. [${crop_width}x${crop_height} ~ X: ${crop_x}, Y: ${crop_y}]"
}

add_propersubs(){
    subs_sign="$(sed -nE 's_^\[sig(n|ns)\](.*)\[/sig(n|ns)\]_[\2]_p' <<< "${subtitle}")"
    subs_normal="$(grep -vE '\[sig(n|ns)\]' <<< "${subtitle}" | sed -E 's|^\[song\](.*)\[/song\]|(\1)|g')"
    
    chk_reso="$(identify -format '%w' "${1}")"
    # contains magic values to make it adaptive
    pt_size="$(bc <<< "${chk_reso} * 0.0234")" pt_size="$(printf "%.0f" "${pt_size}")"
    ant_pos="$(bc <<< "${chk_reso} * 0.0521")" ant_pos="$(printf "%.0f" "${ant_pos}")"
    strk_width="$(bc <<< "${chk_reso} * 0.0042")" strk_width="$(printf "%.0f" "${strk_width}")"
    if [[ -n "${subs_normal}" ]]; then
        if [[ "${single}" == "1" ]]; then
            convert "${1}" -gravity south -undercolor '#00000090' -fill white -font fonts/trebuc.ttf -weight 900 -pointsize "${pt_size}" -annotate +0+"${ant_pos}" "${subs_normal}" output_image.jpg
        else
            reso_perc="$(bc <<< "(0.85*${chk_reso})/1")"
            convert -background none -size "${reso_perc}"x -gravity center -font fonts/forsub.ttf \( -fill black -stroke black -strokewidth "${strk_width}" -pointsize "$((pt_size + 10))" caption:"${subs_normal}" \) -pointsize "$((pt_size + 10))" -fill white -stroke none caption:"${subs_normal}" +composite capt_temp.png
            convert "${1}" \( -gravity south capt_temp.png -geometry "+0+${ant_pos}" \) +composite output_image.jpg
            rm capt_temp.png
        fi
        mv output_image.jpg "${1}"
    fi
    if [[ -n "${subs_sign}" ]]; then
        convert "${1}" -gravity north -undercolor '#00000090' -fill white -font fonts/trebuc.ttf -weight 900 -pointsize "${pt_size}" -annotate +0+"${ant_pos}" "${subs_sign}"  output_image.jpg
        mv output_image.jpg "${1}"
    fi
    [[ "${single}" == "1" ]] || unset subs_sign subs_normal
}

two_panel(){
    for ((i=0;i<=1;i++)); do
        main_br
        scrv3 "$(nth "${selc_frame}")"
        eval timestamp[${i}]="$(nth "${selc_frame}" timestamp)" 
        curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/frames/frame_${selc_frame}.jpg" -o main_frame_"${i}".jpg
        add_propersubs "main_frame_${i}.jpg"
    done
    convert main_frame_* -append main_frame.jpg
    rm main_frame_*
	main_message="$(cat <<-EOF
	[Random Frames]
	Season ${season}, Episode ${episode}, Frame [${selc_frame_old}, ${selc_frame}] (Timestamp: $(sed -E 's| |, |g' <<< "${timestamp[*]}"))
	
	.
	.
	RNG seed: ${seed}
	EOF
	)"
}

mirror_image(){
    IMAGE="main_frame.jpg"
    OFFSET_PERCENTAGE=${1:-50} 
    WIDTH=$(identify -format "%w" "$IMAGE")
    HEIGHT=$(identify -format "%h" "$IMAGE")
    HALF_WIDTH=$((WIDTH / 2))
    OFFSET_PIXELS=$((HALF_WIDTH * OFFSET_PERCENTAGE / 100))
    convert "$IMAGE" -crop "${HALF_WIDTH}x${HEIGHT}+$OFFSET_PIXELS+0" +repage right_half.png
    convert right_half.png -flop mirrored_right_half.png
    rm main_frame.jpg
    convert mirrored_right_half.png right_half.png +append main_frame.jpg
    rm mirrored_right_half.png right_half.png
    has_filter=1
    filter_message+=" --mirror [offset:${OFFSET_PERCENTAGE}]"
}

negative_filter(){
    IMAGE="main_frame.jpg"
    convert main_frame.jpg -negate mainframe_temp.jpg
    has_filter=1
    mv mainframe_temp.jpg main_frame.jpg
    filter_message+=" --negative"
}

generate_palette() {
    input_image="$1"
    num_colors="$2"
    has_filter=1
    original_width="$(identify -format "%w" "${input_image}")"

    palleted="$(convert "${input_image}" -resize 100x100 -colors "${num_colors}" +dither -unique-colors txt:- | grep -oE '#[0-9A-Fa-f]{6}' | head -n "${num_colors}")"

    # calculates brightness
    # source: https://gist.github.com/w3core/e3d9b5b6d69a3ba8671cc84714cca8a4
    get_brightness() {
        local hex="$1"
        local r="${hex:1:2}" g="${hex:3:2}" b="${hex:5:2}"
        r="$((16#$r))" g="$((16#$g))" b="$((16#$b))"
        echo "$(( (299 * r + 587 * g + 114 * b) / 1000 ))"
    }

    color_brightness_pairs=()
    while IFS= read -r color; do
        brightness=$(get_brightness "${color}")
        color_brightness_pairs+=("${brightness} ${color}")
    done <<< "${palleted}"

    sorted_colors="$(printf "%s\n" "${color_brightness_pairs[@]}" | sort -rn | awk '{print $2}')"

    block_width="$((original_width / num_colors))"

    palette_list=()
    for color in ${sorted_colors}; do
        brightness="$(get_brightness "$color")"
        
        if (( brightness < 128 )); then
            text_color="white"
        else
            text_color="black"
        fi

        color_block="b${color}.png"
        convert -size "${block_width}x50" xc:"${color}" \
            -font fonts/helvetica_f.ttf -pointsize 23 -gravity center -fill "${text_color}" -annotate +0+0 "${color}" \
            "${color_block}"
        palette_list+=("${color_block}")
    done

    palette_image="palette.png"
    convert "${palette_list[@]}" +append "${palette_image}"

    convert "${input_image}" "${palette_image}" -append "main_frame_temp.jpg"
    mv main_frame_temp.jpg "${input_image}"
    rm "${palette_image}" "${palette_list[@]}"
    filter_message+=" --pallete [colors:${num_colors}]"
}

main_post(){
    # fair chance to filter
    if [[ "$((RANDOM % 4))" != 0 ]]; then
        main_br
        scrv3 "$(nth "${selc_frame}")"
        timestamp="$(nth "${selc_frame}" timestamp)"
    
        main_message="$(cat <<-EOF
		[Random Frame]
		Season ${season}, Episode ${episode}, Frame ${selc_frame} (Timestamp: ${timestamp})
		
		.
		.
		RNG seed: ${seed}
		EOF
		)"
        curl -sL "https://raw.githubusercontent.com/fearocanity/ebtrfio-bot/${selc_branch}/frames/frame_${selc_frame}.jpg" -o main_frame.jpg
        cp main_frame.jpg main_frame_bak.jpg
        single=1
    else
        two_panel
    fi
    
    if [[ "${single}" == 1 ]]; then
        # unfair chance to filter (prior for the best)
        case "$((RANDOM % 5))" in
            1)
                mirror_image "$(((RANDOM % 100) + 50))"
                ;;
            2)
                negative_filter
                ;;
            3)
                generate_palette "main_frame.jpg" "$(((RANDOM % 5) + 6))"
                ;;
            *)
                true
                ;;
        esac
        [[ "${has_filter}" == 1 ]] && main_message+=$'\n'"Filter:${filter_message}"
    fi
    
    response="$(curl -sfLX POST --retry 2 --retry-connrefused --retry-delay 7 "https://graph.facebook.com/me/photos?access_token=${fb_tok}&published=1" -F "message=${main_message}" -F "source=@main_frame.jpg")"
    idxf="$(printf '%s\n' "${response}" | grep -Po '(?=[0-9])(.*)(?=\",\")')"
    # random crop
    random_crop "main_frame.jpg"
    if [[ -n "${idxf}" ]]; then
        curl -sfLX POST --retry 2 --retry-connrefused --retry-delay 7 "https://graph.facebook.com/v18.0/${idxf}/comments?access_token=${fb_tok}" -F "message=${msg_rc}" -F "source=@output_image.jpg" -o /dev/null
        rm -f output_image.jpg
    fi
    if [[ "${single}" == 1 ]]; then
        # add subs
        add_propersubs "main_frame_bak.jpg"
    
        # post subs
        if [[ -n "${subs_sign}" ]] || [[ -n "${subs_normal}" ]]; then
            curl -sfLX POST --retry 2 --retry-connrefused --retry-delay 7 "https://graph.facebook.com/v18.0/${idxf}/comments?access_token=${fb_tok}" -F "message=Subs:" -F "source=@main_frame.jpg" -o /dev/null
        fi
    fi
    rm main_frame.jpg main_frame_bak.jpg
}

main_post
