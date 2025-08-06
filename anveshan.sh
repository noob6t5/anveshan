#!/bin/bash

# Colors
red=$'\e[91m'; green=$'\e[92m'; yellow=$'\e[93m'; cyan=$'\e[36m'; magenta=$'\e[95m'; reset=$'\e[0m'
export PATH=$PATH:$HOME/.local/bin:$HOME/go/bin

read -p "${magenta}Enter target domain [ex: target.com]: ${reset}" domain
[[ -z "$domain" ]] && { echo -e "${red}[x] No domain provided. Exiting.${reset}"; exit 1; }

echo -e "${red}[!] DNS Bruteforce is DISABLED. Manually handle wildcard crap.${reset}"

# Setup
recon_dir="${domain}-recon"
mkdir -p "$recon_dir" && cd "$recon_dir" || exit

VENV_PATH="$HOME/anveshan/venv"
[[ -d "$VENV_PATH" ]] && source "$VENV_PATH/bin/activate" && echo "[✓] Virtualenv activated" || echo "[!] No virtualenv, using global tools."

# Trap setup
trap 'echo -e "${red}[!] Script interrupted. Moving to next block.${reset}"' SIGINT

# --------------------
# SUBDOMAIN ENUM BLOCK
# --------------------

echo -e "${magenta}[+] Firing subdomain enum tools...${reset}"
mkdir -p knockpy output

timeout 1200 amass enum -passive -d "$domain" -norecursive -nocolor -config $HOME/anveshan/.config/amass/datasources.yaml -o amassP.txt &
pid1=$!
timeout 1200 amass enum -active -d "$domain" -nocolor -config $HOME/anveshan/.config/amass/datasources.yaml -o amassA.txt &
pid2=$!
findomain -t "$domain" -q -u findomain.txt &
pid3=$!
assetfinder --subs-only "$domain" | anew assetfinder.txt &
pid4=$!
subfinder -d "$domain" -all -silent -o subfinder.txt &
pid5=$!
knockpy -d "$domain" --recon --save knockpy 2>/dev/null &
pid6=$!
bbot -t "$domain" -p subdomain-enum -rf passive -o output/bbot.txt --json --no-deps  &
pid7=$!

wait $pid1 $pid2 $pid3 $pid4 $pid5 $pid6 $pid7

[[ -f knockpy/knockpy.json ]] && jq -r '.[].domain' knockpy/knockpy.json | anew knockpy.txt

cat amassP.txt amassA.txt knockpy.txt findomain.txt assetfinder.txt subfinder.txt output/bbot.txt 2>/dev/null | sed 's/\*\.//' | sort -u | anew psubdomains.txt
cp psubdomains.txt subdomains.txt

echo -e "${yellow}[✓] Total subdomains: $(wc -l < subdomains.txt)${reset}"

# --------------------
# HTTPX - LIVE HOSTS
# --------------------

echo -e "${magenta}[*] Probing for live hosts with httpx...${reset}"
httpx-go -l subdomains.txt -threads 50 -silent -title -sc -ip -o httpx.txt

awk '{print $1}' httpx.txt | grep -E '^https?://' | anew webdomains.txt
echo -e "${yellow}[✓] Live web domains: $(wc -l < webdomains.txt)${reset}"

# --------------------
# SCREENSHOT MODULE
# --------------------

echo -e "${cyan}[*] Taking screenshots with gowitness...${reset}"
mkdir -p screenshots/
gowitness scan file -f webdomains.txt --destination screenshots/
echo -e "${yellow}[✓] Screenshots captured.${reset}"

# --------------------
# NAABU - PORT SCAN
# --------------------

echo -e "${magenta}[+] Running naabu on subdomains...${reset}"
naabu -list subdomains.txt -tp 1000 -rate 2000 -o naabu.txt
echo -e "${yellow}[✓] Open ports found: $(wc -l < naabu.txt)${reset}"

# --------------------
# URL & JS ENUM BLOCK
# --------------------

echo -e "${magenta}[*] Collecting URLs, JS & Params...${reset}"
mkdir -p urls && cd urls/

waymore -i "$domain" -mode U -c $HOME/anveshan/.config/waymore/config.yml -oU waymore.txt
getJS --input ../webdomains.txt --output getjs.txt --complete
xnLinkFinder -i waymore.txt -d 3 -sf "$domain" -o xnUrls.txt -op xnParams.txt
cat ../webdomains.txt | hakrawler -depth 2 -subs -t 20 -timeout 10 > hakrawler.txt 2>/dev/null
cat ../webdomains.txt | gau --threads 10 --subs > gau.txt 2>/dev/null
katana -list ../webdomains.txt -jc -em js,json,jsp,jsx,ts,tsx,mjs -d 3 -nc -o katana.txt

cat waymore.txt getjs.txt xnUrls.txt xnParams.txt hakrawler.txt gau.txt katana.txt | sed 's/\x1B\[[0-9;]*[mK]//g' | anew urls.txt

paramspider --domain "$domain" | uro | anew parameters.txt
mkdir -p urls-source/
mv waymore.txt getjs.txt xnUrls.txt katana.txt hakrawler.txt gau.txt urls-source/ 2>/dev/null
cd ..

# --------------------
# JS + NUCLEI + TRUFFLEHOG
# --------------------

echo -e "${magenta}[*] Extracting & analyzing JS files...${reset}"
cat urls/urls.txt | grep -Ei ".+\.js(?:on|p|x)?$" | httpx-go -mc 200 -silent | anew jsurls.txt
httpx-go -l jsurls.txt -sr -ss -pa -title -sc -mc 200 -ct -nc | grep -v "text/html" | cut -d " " -f1 | anew jsfiles.txt

mv output/ js-source/ 2>/dev/null

echo -e "${magenta}[*] Running nuclei for secrets in JS...${reset}"
cat jsfiles.txt | nuclei -t $HOME/nuclei-templates/http/exposures/tokens/ | tee -a js_nuclei.txt

echo -e "${magenta}[*] Scanning JS responses with trufflehog...${reset}"
trufflehog filesystem js-source/response | tee -a trufflehog-src.txt

# --------------------
# IP ENUM
# --------------------

grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' httpx.txt | anew ips.txt
cat subs-source/knockpy/*.json 2>/dev/null | jq '.[] .ip[]' | cut -d '"' -f2 | anew ips.txt

# --------------------
# FINAL STATS
# --------------------

echo -e "${magenta}[*] Recon Summary:${reset}"
echo -e "${red} [+] Subdomains     : ${yellow}$(wc -l < subdomains.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Webdomains     : ${yellow}$(wc -l < webdomains.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Open Ports     : ${yellow}$(wc -l < naabu.txt 2>/dev/null)${reset}"
echo -e "${red} [+] URLs Found     : ${yellow}$(wc -l < urls/urls.txt 2>/dev/null)${reset}"
echo -e "${red} [+] JS Files       : ${yellow}$(wc -l < jsfiles.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Nuclei Secrets : ${yellow}$(wc -l < js_nuclei.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Trufflehog     : ${yellow}$(grep -i 'raw' trufflehog-src.txt 2>/dev/null | wc -l)${reset}"
