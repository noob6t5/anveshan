#!/bin/bash
# Colors
red=$'\e[91m'
green=$'\e[92m'
yellow=$'\e[93m'
cyan=$'\e[36m'
magenta=$'\e[95m'
reset=$'\e[0m'

export PATH=$PATH:$HOME/.local/bin:$HOME/go/bin
# Help menu
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage:"
    echo "${green}  bash anveshan.sh${reset}"
    echo "Options:"
    echo "${green}  --help  Show this help message${reset}"
    exit 0
fi
# Ask for domain
read -p "${magenta}Enter target domain name [ex. target.com] : ${reset}" domain
if [[ -z "$domain" ]]; then
    echo -e "${red}[x] No domain provided. Exiting.${reset}"
    exit 1
fi

# DNS Brute Reminder
echo -e "${red}[!] REMINDER: DNS Bruteforcing is currently DISABLED. Do it manually later.${reset}"
echo ""

# Recon Directory Setup
recon_dir="${domain}-recon"
mkdir -p "$recon_dir" && cd "$recon_dir" || exit

# Activate venv
VENV_PATH="$HOME/anveshan/venv"
if [[ -d "$VENV_PATH" ]]; then
    source "$VENV_PATH/bin/activate"
    echo "Virtual environment activated."
else
    echo "Virtual environment not found. global tools assumed.${reset}."
    exit 1
fi

# -------- SUBDOMAIN ENUM --------
echo "${magenta}[+] running subdominator...${reset}" | pv -qL 20
subdominator -d "$domain" -o subdominator.txt

echo "${magenta}[+] running amass ...${reset}" | pv -qL 20
timeout 1200 amass enum -passive -d "$domain" -norecursive -nocolor -config $HOME/anveshan/.config/amass/datasources.yaml -o amassP
timeout 1200 amass enum -active -d "$domain" -nocolor -config $HOME/anveshan/.config/amass/datasources.yaml -o amassA
cat amassP amassA 2>/dev/null | cut -d " " -f1 | grep "$domain" | anew amass.txt

echo "${magenta}[+] running knock${reset}" | pv -qL 20
mkdir -p knockpy/
knockpy -d "$domain" --recon --save knockpy
cat knockpy/*.json 2>/dev/null | grep '"domain"' | cut -d '"' -f4 | anew knockpy.txt

echo "${magenta}[+] running findomain${reset}" | pv -qL 20
findomain -t "$domain" -u findomain.txt

echo "${magenta}[+] running assetfinder${reset}" | pv -qL 20
assetfinder -subs-only "$domain" | anew assetfinder.txt

echo "${magenta}[+] running subfinder${reset}" | pv -qL 20
subfinder -d "$domain" -all -silent -o subfinder.txt
cat subfinder.txt | anew subfinder_clean.txt

echo "${magenta}[+] running bbot${reset}" | pv -qL 20
"$HOME/.local/bin/bbot" -t "$domain" -f subdomain-enum  -rf passive -o output -n bbot -y
cp output/bbot/subdomains.txt bbot.txt 2>/dev/null

echo "${magenta}[+] running shrewdeye${reset}" | pv -qL 20
bash "$HOME/anveshan/shrewdeye-bash/shrewdeye.sh" -d "$domain"

echo "${yellow}[*] Combining results...${reset}" | pv -qL 20
sed "s/\x1B\[[0-9;]*[mK]//g" *.txt | sed 's/\*\.//g' | anew psubdomains.txt > /dev/null
cp psubdomains.txt subdomains.txt 2>/dev/null

mkdir -p subs-source/
mv subdominator.txt amass.txt amassA amassP knockpy knockpy.txt findomain.txt assetfinder.txt subfinder_clean.txt bbot.txt output/ subs-source/ 2>/dev/null

[[ -f subdomains.txt ]] && echo -e "${yellow}[$] Found $(wc -l < subdomains.txt) subdomains${reset}" | pv -qL 20 || echo "${red}[!] subdomains.txt missing${reset}"

# -------- HTTPX --------
echo "${magenta}[*] Getting webdomains using httpx ${reset}" | pv -qL 20
httpx-go -l subdomains.txt -ss -pa -sc -fr -title -td -location -retries 3 -silent -nc -o httpx.txt
cut -d " " -f1 httpx.txt | anew webdomains.txt

# --- 🔥 Flatten Screenshot Output ---
if [[ -d output ]]; then
    mkdir -p screenshots/
    find output -type f -name '*.png' | while read file; do
        # Extract subdomain folder name and flatten
        subdomain=$(dirname "$file" | sed 's|output/||;s|/.*||')
        filename=$(basename "$file")
        cp "$file" "screenshots/${subdomain}--${filename}"
    done
    rm -rf output/
fi

# -------- IP Collection --------
grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' httpx.txt | anew ips.txt
cat subs-source/knockpy/*.json 2>/dev/null | jq '.[] .ip[]' | cut -d '"' -f2 | anew ips.txt

[[ -f webdomains.txt ]] && echo -e "${yellow}[$] Found $(wc -l < webdomains.txt) webdomains${reset}" | pv -qL 20

# -------- Port Scanning --------
echo "${magenta}[+] Scanning ports using naabu${reset}" | pv -qL 20
naabu -list subdomains.txt -tp 1000 -rate 2000 -o naabu.txt
echo "${yellow}[$] Found $(wc -l < naabu.txt) open ports${reset}" | pv -qL 20

# -------- URL Collection --------
echo "${magenta}[*] Finding URLs${reset}" | pv -qL 20
mkdir -p urls/ && cd urls/

echo "${yellow} [+] waymore ${reset}" | pv -qL 20
waymore -i "$domain" -mode U -c $HOME/anveshan/.config/waymore/config.yml -oU waymore.txt

echo "${yellow} [+] getJS ${reset}" | pv -qL 20
getJS --input ../webdomains.txt --output getjs.txt --complete

echo "${yellow} [+] xnLinkFinder ${reset}" | pv -qL 20
xnLinkFinder -i waymore.txt -d 3 -sf "$domain" -o xnUrls.txt -op xnParams.txt

echo "${yellow} [+] ParamSpider ${reset}" | pv -qL 20
paramspider --domain "$domain" --level high | uro | anew parameters.txt

echo "${yellow} [+] Katana ${reset}" | pv -qL 20
katana -list ../webdomains.txt -jc -em js,json,jsp,jsx,ts,tsx,mjs -d 3 -nc -o katana.txt

# Combine URLs
sed "s/\x1B\[[0-9;]*[mK]//g" waymore.txt getjs.txt xnUrls.txt parameters.txt katana.txt | anew urls.txt
mkdir -p urls-source/ && mv waymore.txt getjs.txt xnUrls.txt katana.txt urls-source/

# -------- JS Files --------
echo "${magenta}[*] Extracting live JS files${reset}" | pv -qL 20
cat urls.txt | grep -Ei ".+\.js(?:on|p|x)?$" | httpx-go -mc 200 | anew jsurls.txt
httpx-go -l jsurls.txt -sr -sc -mc 200 -ct -nc | grep -v "text/html" | cut -d " " -f1 | anew jsfiles.txt
mv output/ ../js-source/ 2>/dev/null
# -------- Nuclei on JS --------
echo "${magenta}[*] Scanning JS files with Nuclei${reset}" | pv -qL 20
cat jsfiles.txt | nuclei -t $HOME/nuclei-templates/http/exposures/tokens/ | tee -a js_nuclei.txt
mv js_nuclei.txt ../

# -------- Trufflehog --------
echo "${magenta}[*] Trufflehog scanning JS source${reset}" | pv -qL 20
trufflehog filesystem ../js-source/response | tee -a trufflehog-src.txt
mv trufflehog-src.txt ../ && cd ../

# -------- HIGHLIGHTS --------
echo "${magenta}[*] Final Recon Stats${reset}" | pv -qL 20
echo -e "${red} [+] Subdomains: ${yellow}$(wc -l < subdomains.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Webdomains: ${yellow}$(wc -l < webdomains.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Open Ports: ${yellow}$(wc -l < naabu.txt 2>/dev/null)${reset}"
echo -e "${red} [+] URLs Found: ${yellow}$(wc -l < urls/urls.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Nuclei Secrets: ${yellow}$(wc -l < js_nuclei.txt 2>/dev/null)${reset}"
echo -e "${red} [+] Trufflehog Secrets: ${yellow}$(grep -i 'raw' trufflehog-src.txt 2>/dev/null | wc -l)${reset}"

