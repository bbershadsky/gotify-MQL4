//+------------------------------------------------------------------+
//|                                         GotifyTradeNotifier.mq4  |
//+------------------------------------------------------------------+
#property copyright "Poseidon Push Gotify"
#property version   "1.0"
#property strict

// External parameters
input string GotifyServer = "";  // No trailing slash, no port
input string GotifyToken = "YOUR_TOKEN";                                    // Your Gotify app token
input int    ScanIntervalSeconds = 1;                                      // How often to check for new trades

string KnownTickets = "";
datetime LastScanTime = 0;

string FormatNumberWithCommas(double value)
{
   string strVal = DoubleToString(value, 2);
   int dotPos = StringFind(strVal, ".");
   
   string integerPart;
   if(dotPos == -1)
      integerPart = strVal;
   else
      integerPart = StringSubstr(strVal, 0, dotPos);
   
   string decimalPart = (dotPos == -1) ? "" : StringSubstr(strVal, dotPos);
   
   string formattedInt = "";
   int len = StringLen(integerPart);
   for(int i = 0; i < len; i++)
   {
      formattedInt = StringSubstr(integerPart, len - 1 - i, 1) + formattedInt;
      if((i + 1) % 3 == 0 && i + 1 < len)
         formattedInt = "," + formattedInt;
   }
   
   return formattedInt + decimalPart;
}

//+------------------------------------------------------------------+
//| Calculate total floating P/L for specific symbol (open positions only) |
//+------------------------------------------------------------------+
double CalculateSymbolFloatingPL(string symbol)
{
   double totalPL = 0.0;
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == symbol && (OrderType() == OP_BUY || OrderType() == OP_SELL))
         {
            totalPL += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   
   return totalPL;
}

//+------------------------------------------------------------------+
//| Calculate current account drawdown % vs balance                   |
//+------------------------------------------------------------------+
double CalculateAccountDrawdownPct()
{
   double balance = AccountBalance();
   double equity = AccountEquity();
   
   if(balance <= 0) return 0.0;
   
   double drawdown = (balance - equity) / balance * 100.0;
   return (drawdown > 0) ? drawdown : 0.0;  // Show 0% if in profit
}


//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate configuration
   if(GotifyServer == "" || GotifyToken == "")
   {
      Alert("ERROR: Please set GotifyServer and GotifyToken in EA properties!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Check for invalid characters in server URL
   if(StringFind(GotifyServer, "[") >= 0 || StringFind(GotifyServer, "]") >= 0 ||
      StringFind(GotifyServer, "(") >= 0 || StringFind(GotifyServer, ")") >= 0)
   {
      Alert("ERROR: GotifyServer contains invalid characters (brackets/parentheses). Use plain URL only.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Check for port in URL (MT4 WebRequest doesn't support custom ports)
   if(StringFind(GotifyServer, ":8080") >= 0 || StringFind(GotifyServer, ":3000") >= 0)
   {
      Alert("ERROR: MT4 WebRequest only supports ports 80/443. Use a tunnel service (Cloudflare, ngrok) to expose on 443.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Initialize known tickets with existing orders
   InitializeKnownTickets();
   
   Print("========================================");
   Print("===== GotifyTradeNotifier Started =====");
   Print("========================================");
   Print("Server: ", GotifyServer);
   Print("Token: ", StringSubstr(GotifyToken, 0, 10), "...");
   Print("Token length: ", StringLen(GotifyToken));
   Print("Scan interval: ", ScanIntervalSeconds, " seconds");
   Print("Initialized with ", OrdersTotal(), " existing orders");
   Print("========================================");
   
   // Set timer for periodic checking (more reliable than OnTick for multi-symbol monitoring)
   EventSetTimer(ScanIntervalSeconds);
   LastScanTime = TimeCurrent();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("GotifyTradeNotifier stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Initialize known tickets from existing orders                     |
//+------------------------------------------------------------------+
void InitializeKnownTickets()
{
   KnownTickets = "";
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(KnownTickets != "") KnownTickets += ",";
         KnownTickets += IntegerToString(OrderTicket());
      }
   }
   
   if(OrdersTotal() > 0)
      Print("Known tickets initialized: ", KnownTickets);
}

//+------------------------------------------------------------------+
//| Timer function (checks for new trades periodically)              |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckForNewTrades();
   LastScanTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert tick function (also checks on price changes)              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Also check on tick for faster detection
   if(TimeCurrent() - LastScanTime >= ScanIntervalSeconds)
   {
      CheckForNewTrades();
      LastScanTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Check for new trades                                              |
//+------------------------------------------------------------------+
void CheckForNewTrades()
{
   int currentOrderCount = OrdersTotal();
   
   for(int i = 0; i < currentOrderCount; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         int ticket = OrderTicket();
         string ticketStr = IntegerToString(ticket);
         
         // Check if this ticket is new
         if(StringFind(KnownTickets, ticketStr) == -1)
         {
            Print("========================================");
            Print("NEW TRADE DETECTED: Ticket #", ticket);
            Print("========================================");
            
            SendGotifyNotification(ticket);
            
            // Add to known tickets
            if(KnownTickets != "") KnownTickets += ",";
            KnownTickets += ticketStr;
            
            Print("Updated known tickets: ", KnownTickets);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions for a specific symbol                       |
//+------------------------------------------------------------------+
int CountPositionsBySymbol(string symbol)
{
   int count = 0;
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == symbol && (OrderType() == OP_BUY || OrderType() == OP_SELL))
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| URL Encode function                                               |
//+------------------------------------------------------------------+
string UrlEncode(string str)
{
   string result = "";
   
   for(int i = 0; i < StringLen(str); i++)
   {
      int ch = StringGetCharacter(str, i);
      
      // Unreserved characters (RFC 3986)
      if((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || 
         (ch >= '0' && ch <= '9') || ch == '-' || ch == '.' || 
         ch == '_' || ch == '~')
      {
         result += CharToString((char)ch);
      }
      else if(ch == ' ')
      {
         result += "%20";
      }
      else
      {
         result += StringFormat("%%%02X", ch & 0xFF);
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Send notification to Gotify                                       |
//+------------------------------------------------------------------+
void SendGotifyNotification(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("ERROR: Failed to select order #", ticket);
      return;
   }
   
   // Collect trade details
   string symbol = OrderSymbol();
   int type = OrderType();
   double lots = OrderLots();
   double openPrice = OrderOpenPrice();
   double tp = OrderTakeProfit();
   double profit = OrderProfit();
   
   // Get last 3 digits of account number
   string accountStr = IntegerToString(AccountNumber());
   string accountLast3 = StringSubstr(accountStr, StringLen(accountStr) - 3, 3);
   
   // Get trade type string
   string tradeType = "";
   if(type == OP_BUY) tradeType = "BUY";
   else if(type == OP_SELL) tradeType = "SELL";
   else if(type == OP_BUYLIMIT) tradeType = "BUY LIMIT";
   else if(type == OP_SELLLIMIT) tradeType = "SELL LIMIT";
   else if(type == OP_BUYSTOP) tradeType = "BUY STOP";
   else if(type == OP_SELLSTOP) tradeType = "SELL STOP";
   
   // Count total positions for this symbol
   int totalPositions = CountPositionsBySymbol(symbol);
   
   // Build concise title
   // Format: 593 EURUSD.p BUY 0.01 1.16758
   string title = accountLast3 + " " + symbol + " " + tradeType + " " + 
                  DoubleToString(lots, 2) + " " + 
                  DoubleToString(openPrice, (int)MarketInfo(symbol, MODE_DIGITS));
   
   // Build concise message
   // Format: TP: 1.17 | P/L: -0.02 | POS: 1/7
   string message = "TP: ";
   if(tp > 0)
      message += DoubleToString(tp, (int)MarketInfo(symbol, MODE_DIGITS));
   else
      message += "None";
   
   message += " | POS: " + IntegerToString(totalPositions);
   
   double symbolPL = CalculateSymbolFloatingPL(symbol);
   double drawdownPct = CalculateAccountDrawdownPct();
   
   // Build concise message
   // Format: SymPL: +12.34 | DD: 1.2%
  message += "SymPL: " + FormatNumberWithCommas(symbolPL) + 
                 " | DD: " + DoubleToString(drawdownPct, 1) + "%";

   
   // Build URL with token as query parameter
   string url = GotifyServer + "/message?token=" + UrlEncode(GotifyToken);
   
   // Build form-encoded body
   string body = "title=" + UrlEncode(title) + 
                 "&message=" + UrlEncode(message) + 
                 "&priority=5";
   
   // Prepare headers - IMPORTANT: Use real \r\n, not \\r\\n
   string requestHeaders = "Content-Type: application/x-www-form-urlencoded\r\n";
   string responseHeaders = "";
   
   // Convert body to char array
   char post[], result[];
   StringToCharArray(body, post, 0, StringLen(body));
   ArrayResize(post, ArraySize(post) - 1); // Remove null terminator
   
   // Reset error before request
   ResetLastError();
   
   Print("Sending notification...");
   Print("Title: ", title);
   Print("Message: ", message);
   
   // Make request
   int timeout = 8000; // 8 seconds
   int httpCode = WebRequest("POST", url, requestHeaders, timeout, post, result, responseHeaders);
   int errorCode = GetLastError();
   
   // Parse response
   string responseBody = CharArrayToString(result, 0, -1);
   
   Print("----------------------------------------");
   Print("HTTP Response Code: ", httpCode);
   Print("GetLastError(): ", errorCode);
   
   // Check result
   if(httpCode == -1)
   {
      Print("*** WEBREQUEST FAILED ***");
      
      if(errorCode == 4014)
      {
         Print("ERROR 4014: URL not in allowed list!");
         Print("SOLUTION: Add ", GotifyServer, " to allowed URLs and restart MT4");
      }
      else if(errorCode == 4060)
      {
         Print("ERROR 4060: WebRequest not allowed!");
      }
      else if(errorCode == 5200)
      {
         Print("ERROR 5200: Invalid URL or unsupported port!");
      }
      else
      {
         Print("ERROR ", errorCode);
      }
   }
   else if(httpCode >= 200 && httpCode < 300)
   {
      Print("*** SUCCESS: Notification sent for ticket #", ticket, " ***");
   }
   else if(httpCode == 400)
   {
      Print("*** HTTP 400: Bad Request - ", responseBody);
   }
   else if(httpCode == 401)
   {
      Print("*** HTTP 401: Invalid token ***");
   }
   else if(httpCode == 404)
   {
      Print("*** HTTP 404: Check GotifyServer URL ***");
   }
   else
   {
      Print("*** HTTP ", httpCode, " ***");
   }
   
   Print("========================================");
}
