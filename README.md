# Spawn Timer Bot

A Discord bot for managing spawn timers.

## Installation

### Prerequisites

1.  **Update package list:**
    ```bash
    sudo apt-get update
    ```

2.  **Install essential packages:**
    ```bash
    sudo apt-get install build-essential gnupg2 git libpq-dev
    ```

3.  **Install RVM (Ruby Version Manager):**
    
    Follow the instructions on the official RVM website: [https://rvm.io/](https://rvm.io/)

4.  **Install Ruby:**
    
    Once RVM is installed, install a recent version of Ruby:
    ```bash
    rvm install 3.4.7
    rvm use 3.4.7 --default
    ```

### Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/iandev/spawn-timer-bot.git
    cd spawn-timer-bot
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    ```

3.  **Configure environment variables:**
    
    Copy the example template:
    ```bash
    cp .env.template .env
    ```
    
    Then, edit the `.env` file with your specific settings (e.g., Discord bot token).

## Running the Bot

### Start the Bot

To start the Discord bot, run:
```bash
bundle exec ruby bot.rb
```

### Start the Web App

To start the web interface, run:
```bash
bundle exec ruby webapp.rb
```
