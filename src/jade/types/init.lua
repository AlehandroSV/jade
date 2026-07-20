local types = {
    String = require("jade.types.string"),
    Integer = require("jade.types.integer"),
    Boolean = require("jade.types.boolean"),
    Text = require("jade.types.text"),
    Timestamp = require("jade.types.timestamp"),
    Float = require("jade.types.float"),
    Decimal = require("jade.types.decimal"),
    UUID = require("jade.types.uuid"),
    Date = require("jade.types.date"),
    CUID = require("jade.types.cuid"),
    NanoID = require("jade.types.nanoid"),
    BigInt = require("jade.types.bigint"),
    JSON = require("jade.types.json"),
    Enum = require("jade.types.enum"),
}

return types
