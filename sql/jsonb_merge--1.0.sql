/* jsonb_merge--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION jsonb_merge" to load this file. \quit

-- Create the function that will be exposed to SQL
CREATE OR REPLACE FUNCTION jsonb_merge(jsonb, jsonb)
RETURNS jsonb
AS 'MODULE_PATHNAME', 'jsonb_merge'
LANGUAGE C IMMUTABLE;

-- Add a comment to explain what the function does
COMMENT ON FUNCTION jsonb_merge(jsonb, jsonb) IS 'Merges two JSONB values, with the second one taking precedence on conflicts';
