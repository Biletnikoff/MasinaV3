#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <regex>
struct NetworkUsage
{
    unsigned long rx_bytes;
    unsigned long tx_bytes;
};
NetworkUsage getNetworkUsage()
{
    std::ifstream netDevFile("/proc/net/dev");
    std::string line;
    NetworkUsage usage = {0, 0};

    // Skip the first two lines (header lines)
    std::getline(netDevFile, line);
    std::getline(netDevFile, line);

    while (std::getline(netDevFile, line))
    {
        std::istringstream iss(line);
        std::string iface;
        iss >> iface;

        // Remove trailing colon from the interface name
        iface.pop_back();

        // Skip the unwanted interfaces
        if (iface != "lo")
        {
            unsigned long rx_bytes, tx_bytes;
            iss >> rx_bytes; // read rx_bytes
            for (int i = 0; i < 7; ++i)
                iss >> tx_bytes; // skip to tx_bytes
            iss >> tx_bytes;     // read tx_bytes

            usage.rx_bytes += rx_bytes;
            usage.tx_bytes += tx_bytes;
        }
    }

    return usage;
}

int get_cpu_temperature()
{
    std::ifstream file("/sys/class/thermal/thermal_zone0/temp");
    if (!file.is_open())
    {
        std::cerr << "Error: Unable to open temperature file." << std::endl;
        return -1;
    }

    std::string line;
    std::getline(file, line);
    file.close();

    try
    {
        return std::stoi(line) / 1000;
    }
    catch (const std::exception& e)
    {
        std::cerr << "Error: Failed to parse temperature: " << e.what() << std::endl;
        return -1;
    }
}

void getSignalStrength(int& rssi, int& snr) {
    const char* command = "mmcli -m 0 --signal-get 2>/dev/null";

    FILE* fp = popen(command, "r");
    if (fp == nullptr) {
        rssi = -1;
        snr = -1;
        return;
    }

    char buffer[256];
    std::string output;
    while (fgets(buffer, sizeof(buffer), fp) != nullptr) {
        output += buffer;
    }
    pclose(fp);

    std::regex rssiRegex("rssi:\\s*([-\\d\\.]+)");
    std::regex snrRegex("snr:\\s*([-\\d\\.]+)");
    std::smatch match;

    if (std::regex_search(output, match, rssiRegex) && match.size() > 1)
        rssi = static_cast<int>(std::stof(match[1].str()));
    else
        rssi = -1;

    if (std::regex_search(output, match, snrRegex) && match.size() > 1)
        snr = static_cast<int>(std::stof(match[1].str()));
    else
        snr = -1;
}
std::string getServingCellInfo() {
    const char* command = "/home/zodiac118/client/at_command";
    
    // Open a pipe to execute the command
    FILE* fp = popen(command, "r");
    if (fp == nullptr) {
        std::cerr << "Failed to run command" << std::endl;
        return "";
    }

    // Read the output of the command
    char buffer[256];
    std::string output;
    while (fgets(buffer, sizeof(buffer), fp) != nullptr) {
        output += buffer;
    }

    // Close the pipe
    pclose(fp);

    return output;
}